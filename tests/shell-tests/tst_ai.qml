import QtQuick
import QtTest
import Quickshell
import qs.services
import qs.services.ai
import qs.modules.common

/**
 * Tests for the AI service and its API strategies.
 *
 * The strategies are plain QML objects, so the test can create them and
 * feed them a recorded payload instead of talking to a real endpoint.
 */
TestCase {
    id: testCase
    name: "Ai"
    when: true

    function test_a_gemini_request_carries_the_contents_and_the_system_prompt() {
        const model = Ai.aiModelComponent.createObject(null, {
            "name": "Test",
            "endpoint": "https://example.invalid/v1",
            "model": "gemini-test",
            "api_format": "gemini"
        });
        const strategy = Ai.geminiApiStrategy.createObject(null);

        const data = strategy.buildRequestData(
            model,
            [{ role: "user", rawContent: "hello", content: "hello" }],
            "be brief",
            0.25,
            [],
            ""
        );

        compare(data.contents.length, 1);
        compare(data.contents[0].role, "user");
        compare(data.contents[0].parts[0].text, "hello");
        compare(data.system_instruction.parts[0].text, "be brief");
        compare(data.generationConfig.temperature, 0.25);
        compare(data.tools.length, 0);
    }

    function test_a_gemini_request_maps_the_assistant_role_to_model() {
        const model = Ai.aiModelComponent.createObject(null, {
            "name": "Test",
            "endpoint": "https://example.invalid/v1",
            "model": "gemini-test",
            "api_format": "gemini"
        });
        const strategy = Ai.geminiApiStrategy.createObject(null);

        const data = strategy.buildRequestData(
            model,
            [{ role: "assistant", rawContent: "answer", content: "answer" }],
            "",
            0.5,
            [],
            ""
        );

        compare(data.contents[0].role, "model");
        compare(data.contents[0].parts[0].text, "answer");
    }

    function test_the_gemini_endpoint_carries_the_api_key_placeholder() {
        const model = Ai.aiModelComponent.createObject(null, {
            "name": "Test",
            "endpoint": "https://example.invalid/v1",
            "model": "gemini-test",
            "api_format": "gemini"
        });
        const strategy = Ai.geminiApiStrategy.createObject(null);

        compare(strategy.buildEndpoint(model), "https://example.invalid/v1?key=${API_KEY}");
    }

    function test_the_openai_request_puts_the_system_prompt_first() {
        const model = Ai.aiModelComponent.createObject(null, {
            "name": "Test",
            "endpoint": "https://example.invalid/v1",
            "model": "openai-test",
            "api_format": "openai"
        });
        const strategy = Ai.openaiApiStrategy.createObject(null);

        const data = strategy.buildRequestData(
            model,
            [{ role: "user", rawContent: "hello", content: "hello" }],
            "be brief",
            0.75,
            [],
            ""
        );

        compare(data.model, "openai-test");
        compare(data.stream, true);
        compare(data.temperature, 0.75);
        compare(data.messages.length, 2);
        compare(data.messages[0].role, "system");
        compare(data.messages[0].content, "be brief");
        compare(data.messages[1].role, "user");
        compare(data.messages[1].content, "hello");
    }

    function test_the_openai_authorization_header_uses_the_api_key_variable() {
        const strategy = Ai.openaiApiStrategy.createObject(null);
        compare(strategy.buildAuthorizationHeader("API_KEY"), "-H \"Authorization: Bearer ${API_KEY}\"");
    }

    function test_a_gemini_stream_is_parsed_into_the_message() {
        const strategy = Ai.geminiApiStrategy.createObject(null);
        const message = Ai.aiMessageComponent.createObject(null, {
            "role": "assistant", "content": "", "rawContent": ""
        });

        strategy.parseResponseLine("[", message);
        strategy.parseResponseLine('{"candidates":[{"content":{"parts":[{"text":"Hello there"}],"role":"model"}}],"usageMetadata":{"promptTokenCount":3,"candidatesTokenCount":5,"totalTokenCount":8}}', message);
        const result = strategy.parseResponseLine("]", message);

        compare(message.content, "Hello there");
        compare(message.rawContent, "Hello there");
        compare(result.tokenUsage.input, 3);
        compare(result.tokenUsage.output, 5);
        compare(result.tokenUsage.total, 8);
    }

    function test_a_gemini_error_payload_is_reported_in_the_message() {
        const strategy = Ai.geminiApiStrategy.createObject(null);
        const message = Ai.aiMessageComponent.createObject(null, {
            "role": "assistant", "content": "", "rawContent": ""
        });

        strategy.parseResponseLine("[", message);
        strategy.parseResponseLine('{"error":{"code":400,"message":"Bad key"}}', message);
        const result = strategy.parseResponseLine("]", message);

        compare(message.content, "**Error 400**: Bad key");
        compare(result.finished, true);
    }

    function test_an_openai_stream_line_is_appended_to_the_message() {
        const strategy = Ai.openaiApiStrategy.createObject(null);
        const message = Ai.aiMessageComponent.createObject(null, {
            "role": "assistant", "content": "", "rawContent": ""
        });

        strategy.parseResponseLine('data: {"choices":[{"delta":{"content":"Hi"}}]}', message);
        compare(message.content, "Hi");
    }

    function test_an_openai_error_payload_is_reported_in_the_message() {
        const strategy = Ai.openaiApiStrategy.createObject(null);
        const message = Ai.aiMessageComponent.createObject(null, {
            "role": "assistant", "content": "", "rawContent": ""
        });

        const result = strategy.parseResponseLine('data: {"error":{"message":"boom"}}', message);

        compare(message.content, "**Error**: boom");
        compare(result.finished, true);
    }

    function test_the_service_exposes_the_shipped_models() {
        verify(Object.keys(Ai.models).includes("gemini-2.5-flash"));
        verify(Object.keys(Ai.models).includes("mistral-medium-latest"));
        compare(Ai.models["gemini-2.5-flash"].api_format, "gemini");
        compare(Ai.models["mistral-medium-latest"].api_format, "mistral");
        compare(Ai.apiKeyEnvVarName, "API_KEY");
    }

    function test_safe_model_name_replaces_the_characters_a_path_cannot_hold() {
        compare(Ai.safeModelName("llama3:8b"), "llama3_8b");
        compare(Ai.safeModelName("a b"), "a-b");
        compare(Ai.safeModelName("a/b"), "a-b");
    }
}
