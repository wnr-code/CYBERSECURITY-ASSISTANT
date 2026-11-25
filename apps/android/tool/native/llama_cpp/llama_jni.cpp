#include <jni.h>
#include <llama.h>

#include <algorithm>
#include <cstdint>
#include <mutex>
#include <string>
#include <thread>
#include <vector>

namespace {
std::mutex runtime_mutex;
llama_model * model = nullptr;
llama_context * context = nullptr;

std::string from_utf8_bytes(JNIEnv * env, jbyteArray value) {
    if (value == nullptr) return {};
    const jsize size = env->GetArrayLength(value);
    std::string result(static_cast<size_t>(size), '\0');
    if (size > 0) env->GetByteArrayRegion(value, 0, size, reinterpret_cast<jbyte *>(result.data()));
    return result;
}

jbyteArray to_utf8_bytes(JNIEnv * env, const std::string & value) {
    auto result = env->NewByteArray(static_cast<jsize>(value.size()));
    if (result != nullptr && !value.empty()) {
        env->SetByteArrayRegion(result, 0, static_cast<jsize>(value.size()), reinterpret_cast<const jbyte *>(value.data()));
    }
    return result;
}

std::vector<std::string> read_string_array(JNIEnv * env, jobjectArray values) {
    std::vector<std::string> result;
    if (values == nullptr) return result;
    const jsize length = env->GetArrayLength(values);
    result.reserve(static_cast<size_t>(length));
    for (jsize i = 0; i < length; ++i) {
        auto bytes = static_cast<jbyteArray>(env->GetObjectArrayElement(values, i));
        result.push_back(from_utf8_bytes(env, bytes));
        if (bytes != nullptr) env->DeleteLocalRef(bytes);
        if (env->ExceptionCheck()) return {};
    }
    return result;
}

jboolean native_load_model(JNIEnv * env, jobject, jstring model_path) {
    if (model_path == nullptr) return JNI_FALSE;
    const char * path = env->GetStringUTFChars(model_path, nullptr);
    if (path == nullptr) return JNI_FALSE;
    std::lock_guard<std::mutex> lock(runtime_mutex);
    if (context != nullptr) {
        llama_free(context);
        context = nullptr;
    }
    if (model != nullptr) {
        llama_model_free(model);
        model = nullptr;
    }
    llama_backend_init();
    auto model_params = llama_model_default_params();
    model_params.n_gpu_layers = 0; // hard CPU-only invariant
    model = llama_model_load_from_file(path, model_params);
    env->ReleaseStringUTFChars(model_path, path);
    if (model == nullptr) return JNI_FALSE;

    auto context_params = llama_context_default_params();
    context_params.n_ctx = 2048;
    context_params.n_batch = 256;
    const auto detected_threads = std::thread::hardware_concurrency();
    const int32_t thread_count = static_cast<int32_t>(std::clamp(detected_threads == 0 ? 2u : detected_threads, 1u, 4u));
    context_params.n_threads = thread_count;
    context_params.n_threads_batch = thread_count;
    context = llama_init_from_model(model, context_params);
    if (context == nullptr) {
        llama_model_free(model);
        model = nullptr;
        return JNI_FALSE;
    }
    return JNI_TRUE;
}

void native_unload_model(JNIEnv *, jobject) {
    std::lock_guard<std::mutex> lock(runtime_mutex);
    if (context != nullptr) llama_free(context);
    if (model != nullptr) llama_model_free(model);
    context = nullptr;
    model = nullptr;
}

jbyteArray native_complete(JNIEnv * env, jobject, jobjectArray role_values, jobjectArray content_values, jint max_tokens) {
    const auto roles = read_string_array(env, role_values);
    const auto contents = read_string_array(env, content_values);
    if (env->ExceptionCheck() || roles.empty() || roles.size() != contents.size() || roles.size() > 32 || max_tokens < 1 || max_tokens > 512) {
        return nullptr;
    }
    std::lock_guard<std::mutex> lock(runtime_mutex);
    if (model == nullptr || context == nullptr) return nullptr;
    const char * chat_template = llama_model_chat_template(model, nullptr);
    if (chat_template == nullptr) return nullptr;

    std::vector<llama_chat_message> messages;
    messages.reserve(roles.size());
    size_t input_bytes = 0;
    for (size_t i = 0; i < roles.size(); ++i) {
        if (roles[i] != "user" && roles[i] != "assistant" && roles[i] != "system") return nullptr;
        input_bytes += roles[i].size() + contents[i].size();
        if (input_bytes > 16 * 1024) return nullptr;
        messages.push_back({roles[i].c_str(), contents[i].c_str()});
    }
    int32_t prompt_size = static_cast<int32_t>(std::min<size_t>(input_bytes * 3 + 256, 64 * 1024));
    std::vector<char> prompt(static_cast<size_t>(prompt_size));
    int32_t formatted = llama_chat_apply_template(chat_template, messages.data(), messages.size(), true, prompt.data(), prompt_size);
    if (formatted < 0 || formatted > 64 * 1024) return nullptr;
    if (formatted >= prompt_size) {
        prompt.resize(static_cast<size_t>(formatted) + 1);
        formatted = llama_chat_apply_template(chat_template, messages.data(), messages.size(), true, prompt.data(), static_cast<int32_t>(prompt.size()));
        if (formatted < 0 || static_cast<size_t>(formatted) >= prompt.size()) return nullptr;
    }

    const llama_vocab * vocab = llama_model_get_vocab(model);
    const int32_t token_count = -llama_tokenize(vocab, prompt.data(), formatted, nullptr, 0, true, true);
    if (token_count <= 0 || token_count > 4096 || static_cast<uint32_t>(token_count + max_tokens) > llama_n_ctx(context)) return nullptr;
    std::vector<llama_token> tokens(static_cast<size_t>(token_count));
    if (llama_tokenize(vocab, prompt.data(), formatted, tokens.data(), token_count, true, true) < 0) return nullptr;

    llama_memory_clear(llama_get_memory(context), true);
    auto * batch = llama_batch_ext_init(context);
    if (batch == nullptr) return nullptr;
    auto sampler_params = llama_sampler_chain_default_params();
    auto * sampler = llama_sampler_chain_init(sampler_params);
    if (sampler == nullptr) {
        llama_batch_ext_free(batch);
        return nullptr;
    }
    llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40));
    llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9f, 1));
    llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.7f));
    llama_sampler_chain_add(sampler, llama_sampler_init_dist(LLAMA_DEFAULT_SEED));

    std::string output;
    bool failed = false;
    llama_pos position = 0;
    size_t cursor = 0;
    const size_t batch_capacity = std::max<uint32_t>(1, llama_n_batch(context));
    // Prefill in bounded batches; the prompt may be longer than llama.cpp's
    // physical batch size while still fitting the configured context.
    while (cursor < tokens.size()) {
        llama_batch_ext_clear(batch);
        const size_t count = std::min(batch_capacity, tokens.size() - cursor);
        int32_t final_index = -1;
        for (size_t i = 0; i < count; ++i) {
            const int32_t index = llama_batch_ext_add_token(batch, 0, tokens[cursor++]);
            if (index < 0) { failed = true; break; }
            const llama_pos token_position = position++;
            if (!llama_batch_ext_set_pos(batch, index, &token_position)) { failed = true; break; }
            final_index = index;
        }
        if (failed || final_index < 0) { failed = true; break; }
        const bool last_prompt_batch = cursor == tokens.size();
        if ((last_prompt_batch && !llama_batch_ext_set_output_logits(batch, final_index, true)) ||
            llama_process(context, LLAMA_PROCESS_TYPE_DECODE, batch) != 0) {
            failed = true;
            break;
        }
    }

    for (int32_t generated = 0; !failed && generated < max_tokens; ++generated) {
        llama_token next_token = llama_sampler_sample(sampler, context, -1);
        if (llama_vocab_is_eog(vocab, next_token)) break;
        char piece[512];
        const int32_t piece_size = llama_token_to_piece(vocab, next_token, piece, sizeof(piece), 0, false);
        if (piece_size < 0 || output.size() + static_cast<size_t>(piece_size) > 12 * 1024) { failed = true; break; }
        output.append(piece, static_cast<size_t>(piece_size));
        llama_sampler_accept(sampler, next_token);
        if (generated + 1 >= max_tokens || static_cast<uint32_t>(position) >= llama_n_ctx(context)) break;

        llama_batch_ext_clear(batch);
        const int32_t index = llama_batch_ext_add_token(batch, 0, next_token);
        if (index < 0) { failed = true; break; }
        const llama_pos token_position = position++;
        if (!llama_batch_ext_set_pos(batch, index, &token_position) ||
            !llama_batch_ext_set_output_logits(batch, index, true) ||
            llama_process(context, LLAMA_PROCESS_TYPE_DECODE, batch) != 0) {
            failed = true;
        }
    }
    llama_sampler_free(sampler);
    llama_batch_ext_free(batch);
    return failed ? nullptr : to_utf8_bytes(env, output);
}

JNINativeMethod methods[] = {
    {const_cast<char *>("nativeLoadModel"), const_cast<char *>("(Ljava/lang/String;)Z"), reinterpret_cast<void *>(native_load_model)},
    {const_cast<char *>("nativeUnloadModel"), const_cast<char *>("()V"), reinterpret_cast<void *>(native_unload_model)},
    {const_cast<char *>("nativeComplete"), const_cast<char *>("([[B[[BI)[B"), reinterpret_cast<void *>(native_complete)},
};
} // namespace

JNIEXPORT jint JNICALL JNI_OnLoad(JavaVM * vm, void *) {
    JNIEnv * env = nullptr;
    if (vm->GetEnv(reinterpret_cast<void **>(&env), JNI_VERSION_1_6) != JNI_OK) return JNI_ERR;
    jclass bridge = env->FindClass("__ANDROID_PACKAGE__/LocalAiInferenceBridge");
    if (bridge == nullptr) return JNI_ERR;
    if (env->RegisterNatives(bridge, methods, sizeof(methods) / sizeof(methods[0])) != JNI_OK) return JNI_ERR;
    return JNI_VERSION_1_6;
}
