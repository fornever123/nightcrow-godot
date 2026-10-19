"""打包要推到 GitHub 的文件（给 GitHub MCP push_files 用）。
用法：python3 tools/dev/mkpush.py 输出.json "提交说明" 文件1 文件2 ...   （环境变量 BRANCH 默认 trial-wip4）"""
import json, os, sys
out, msg, files = sys.argv[1], sys.argv[2], sys.argv[3:]
d = {"owner": "fornever123", "repo": "nightcrow-godot", "branch": os.environ.get("BRANCH", "trial-wip4"), "message": msg,
     "files": [{"path": f, "content": open(f, encoding="utf-8").read()} for f in files]}
json.dump(d, open(out, "w", encoding="utf-8"), ensure_ascii=False)
print(len(files), "files")
