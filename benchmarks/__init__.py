"""OpenHands Benchmarking Suite"""

# Normalize proxy env vars so httpx accepts them (it only supports socks5://, not socks://)
import os

for _var in (
    "HTTP_PROXY",
    "HTTPS_PROXY",
    "ALL_PROXY",
    "http_proxy",
    "https_proxy",
    "all_proxy",
):
    _val = os.environ.get(_var)
    if _val and isinstance(_val, str) and _val.strip().lower().startswith("socks://"):
        os.environ[_var] = "socks5://" + _val[8:]  # socks:// -> socks5://

# Pre-import these tools to register pydantic models
# for serialization/deserialization.
from openhands.tools.file_editor import FileEditorTool  # noqa: F401
from openhands.tools.task_tracker import TaskTrackerTool  # noqa: F401
from openhands.tools.terminal import TerminalTool  # noqa: F401
from openhands.tools.fuzz_hypo import FuzzHypoTool  # noqa: F401