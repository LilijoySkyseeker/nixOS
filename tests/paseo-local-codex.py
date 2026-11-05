"""Read effective local/cloud Codex settings without starting a model turn."""

import json
import os
import selectors
import subprocess
import time


def read_config(provider):
    process = subprocess.Popen(
        provider["command"] + ["app-server", "--strict-config"],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        env=os.environ | provider.get("env", {}),
    )
    try:
        for request in [
            {
                "id": 1,
                "method": "initialize",
                "params": {"clientInfo": {"name": "local_settings_test", "version": "1"}},
            },
            {"method": "initialized"},
            {"id": 2, "method": "config/read", "params": {"includeLayers": False}},
        ]:
            process.stdin.write(json.dumps(request) + "\n")
            process.stdin.flush()
        with selectors.DefaultSelector() as selector:
            selector.register(process.stdout, selectors.EVENT_READ)
            deadline = time.monotonic() + 30
            while time.monotonic() < deadline:
                if not selector.select(1):
                    continue
                line = process.stdout.readline()
                assert line, "Codex exited before returning its settings"
                response = json.loads(line)
                if response.get("id") == 2:
                    assert "error" not in response, response
                    return response["result"]["config"]
            raise AssertionError("Codex config/read timed out")
    finally:
        process.terminate()
        try:
            process.wait(timeout=5)
        except subprocess.TimeoutExpired:
            process.kill()
            process.wait()


with open("/home/agent/.paseo/config.json") as source:
    providers = json.load(source)["agents"]["providers"]
local = read_config(providers["local-codex"])
assert local["model_context_window"] == 131072, local
assert local["model_auto_compact_token_limit"] == 32768, local
assert local["model_provider"] == "local", local
backend = local["model_providers"]["local"]
assert backend["base_url"] == "http://127.0.0.1:8080/v1", backend
assert backend["wire_api"] == "responses", backend
assert backend["stream_idle_timeout_ms"] == 900000, backend
cloud = read_config(providers["codex"])
assert cloud["model_provider"] != "local", cloud
assert cloud["model_context_window"] is None, cloud
assert cloud["model_auto_compact_token_limit"] is None, cloud
print("Local settings reach Codex; cloud settings remain independent")
