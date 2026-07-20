"""验证 Langfuse 开源版 7 天 Trace 清理脚本的稳定合同。"""

from __future__ import annotations

import contextlib
import http.server
import json
from pathlib import Path
import tempfile
import threading
import types
import unittest
from urllib.parse import parse_qs, urlparse


RESOURCE_TYPE = Path(__file__).parents[1] / "resource-type-langfuse-retention.yaml"


def load_retention_module() -> types.ModuleType:
    """从 ResourceType ConfigMap 中提取真实脚本，避免测试一份复制实现。"""

    text = RESOURCE_TYPE.read_text(encoding="utf-8")
    marker = "          retention.py: |\n"
    _, script_block = text.split(marker, 1)
    lines: list[str] = []
    for line in script_block.splitlines():
        if line and not line.startswith("            "):
            break
        lines.append(line[12:] if line else "")
    module = types.ModuleType("langfuse_retention")
    exec(compile("\n".join(lines), str(RESOURCE_TYPE), "exec"), module.__dict__)
    return module


class MemoryCheckpointStore:
    """测试用 checkpoint，不接触真实 Kubernetes API。"""

    def __init__(self, state: dict[str, object] | None = None) -> None:
        self.state = state
        self.writes: list[dict[str, object]] = []

    def load(self) -> dict[str, object] | None:
        return self.state

    def save(self, state: dict[str, object]) -> None:
        self.state = dict(state)
        self.writes.append(dict(state))


class ApiHandler(http.server.BaseHTTPRequestHandler):
    """只返回虚构 Trace ID 的 Langfuse API 测试替身。"""

    pages: dict[int, list[str]] = {}
    delete_statuses: dict[str, int] = {}
    requests: list[tuple[str, str]] = []

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        page = int(query.get("page", ["1"])[0])
        limit = int(query.get("limit", ["0"])[0])
        self.__class__.requests.append(("GET", self.path))
        data = [{"id": trace_id} for trace_id in self.__class__.pages.get(page, [])]
        payload = {
            "data": data,
            "meta": {
                "page": page,
                "limit": limit,
                "totalItems": sum(len(items) for items in self.__class__.pages.values()),
                "totalPages": max(self.__class__.pages, default=0),
            },
        }
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(payload).encode())

    def do_DELETE(self) -> None:  # noqa: N802
        trace_id = self.path.rsplit("/", 1)[-1]
        self.__class__.requests.append(("DELETE", self.path))
        self.send_response(self.__class__.delete_statuses.get(trace_id, 200))
        self.end_headers()

    def log_message(self, _format: str, *_args: object) -> None:
        return


@contextlib.contextmanager
def fake_api(pages: dict[int, list[str]], statuses: dict[str, int] | None = None):
    """启动线程内 HTTP Server 并在测试结束后可靠关闭。"""

    ApiHandler.pages = pages
    ApiHandler.delete_statuses = statuses or {}
    ApiHandler.requests = []
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), ApiHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        yield f"http://127.0.0.1:{server.server_port}"
    finally:
        server.shutdown()
        thread.join(timeout=2)
        server.server_close()


class LangfuseRetentionTests(unittest.TestCase):
    """覆盖 UTC、分页、幂等、失败和运行预算。"""

    @classmethod
    def setUpClass(cls) -> None:
        cls.module = load_retention_module()

    def runner(self, base_url: str, store: MemoryCheckpointStore, **kwargs: object):
        return self.module.RetentionRunner(
            base_url=base_url,
            public_key="pk-lf-test-only",
            secret_key="sk-lf-test-only",
            retention_days=7,
            batch_size=30,
            max_runtime_seconds=300,
            checkpoint_store=store,
            **kwargs,
        )

    def test_cutoff_is_utc_and_exactly_seven_days(self) -> None:
        now = self.module.datetime(2026, 7, 20, 12, 30, tzinfo=self.module.timezone.utc)
        self.assertEqual(self.module.compute_cutoff(now, 7), "2026-07-13T12:30:00Z")

    def test_uses_limit_30_and_advances_pages(self) -> None:
        with fake_api({1: ["trace-a"], 2: ["trace-b"]}) as base_url:
            store = MemoryCheckpointStore()
            result = self.runner(base_url, store).run()
        get_paths = [path for method, path in ApiHandler.requests if method == "GET"]
        self.assertIn("page=1", get_paths[0])
        self.assertIn("limit=30", get_paths[0])
        self.assertIn("fields=core", get_paths[0])
        self.assertIn("page=2", get_paths[1])
        self.assertEqual(result["deleted"], 2)
        self.assertEqual(store.state["status"], "completed")

    def test_repeated_delete_404_is_idempotent(self) -> None:
        with fake_api({1: ["trace-gone"]}, {"trace-gone": 404}) as base_url:
            result = self.runner(base_url, MemoryCheckpointStore()).run()
        self.assertEqual(result["deleted"], 1)
        self.assertEqual(result["last_error_code"], None)

    def test_429_fails_and_keeps_current_page_checkpoint(self) -> None:
        with fake_api({1: ["trace-rate-limited"]}, {"trace-rate-limited": 429}) as base_url:
            store = MemoryCheckpointStore()
            with self.assertRaises(self.module.RetentionHttpError):
                self.runner(base_url, store).run()
        self.assertEqual(store.state["page"], 1)
        self.assertEqual(store.state["last_error_code"], 429)
        self.assertEqual(store.state["status"], "failed")

    def test_5xx_fails_without_persisting_trace_id(self) -> None:
        with fake_api({1: ["trace-server-error"]}, {"trace-server-error": 503}) as base_url:
            store = MemoryCheckpointStore()
            with self.assertRaises(self.module.RetentionHttpError):
                self.runner(base_url, store).run()
        self.assertEqual(store.state["last_error_code"], 503)
        self.assertNotIn("trace_id", store.state)

    def test_resumes_failed_checkpoint_without_trace_content(self) -> None:
        store = MemoryCheckpointStore(
            {
                "cutoff": "2026-07-13T00:00:00Z",
                "page": 2,
                "deleted": 30,
                "status": "failed",
                "last_error_code": 503,
            }
        )
        with fake_api({1: ["trace-old-page"], 2: ["trace-resumed"]}) as base_url:
            self.runner(base_url, store).run()
        first_get = next(path for method, path in ApiHandler.requests if method == "GET")
        self.assertIn("page=2", first_get)
        self.assertEqual(
            set(store.state),
            {"cutoff", "page", "deleted", "status", "last_error_code"},
        )

    def test_runtime_budget_stops_before_next_page(self) -> None:
        ticks = iter([0.0, 0.0, 0.0, 301.0])
        with fake_api({1: ["trace-budget"], 2: ["trace-not-reached"]}) as base_url:
            store = MemoryCheckpointStore()
            result = self.runner(base_url, store, monotonic=lambda: next(ticks)).run()
        self.assertEqual(result["status"], "partial")
        self.assertEqual(store.state["page"], 2)
        self.assertFalse(any("trace-not-reached" in path for _, path in ApiHandler.requests))


if __name__ == "__main__":
    unittest.main()
