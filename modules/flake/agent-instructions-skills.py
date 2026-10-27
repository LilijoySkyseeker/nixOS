# each skill's frontmatter, parsed as YAML: `name` is its folder, and
# `description` is 1-1,024 characters (Agent Skills spec)
# usage: agent-instructions-skills.py <skills dir>...
import pathlib
import sys

import yaml


class UniqueKeyLoader(yaml.SafeLoader):
    # a repeated key would otherwise let the last value win unseen
    def construct_mapping(self, node, deep=False):
        keys = [self.construct_object(k, deep=deep) for k, _ in node.value]
        dupes = sorted({str(k) for k in keys if keys.count(k) > 1})
        if dupes:
            raise yaml.constructor.ConstructorError(None, None, f"repeated keys {dupes}", node.start_mark)
        return super().construct_mapping(node, deep=deep)


bad = []
for root in sys.argv[1:]:
    for folder in sorted(p for p in pathlib.Path(root).iterdir() if p.is_dir()):
        md = folder / "SKILL.md"
        if not md.is_file():
            bad.append(f"{folder.name}: no SKILL.md")
            continue
        text = md.read_text(encoding="utf-8")
        parts = text.split("\n---\n", 1)
        if not text.startswith("---\n") or len(parts) < 2:
            bad.append(f"{folder.name}: no frontmatter between --- lines")
            continue
        try:
            meta = yaml.load(parts[0][4:] + "\n", Loader=UniqueKeyLoader)
        except yaml.YAMLError as e:
            bad.append(f"{folder.name}: frontmatter isn't YAML: {e}")
            continue
        if not isinstance(meta, dict):
            bad.append(f"{folder.name}: frontmatter isn't a mapping")
            continue
        if meta.get("name") != folder.name:
            bad.append(f"{folder.name}: name is {meta.get('name')!r}")
        desc = meta.get("description")
        if not isinstance(desc, str) or not desc.strip() or len(desc) > 1024:
            n = len(desc) if isinstance(desc, str) else None
            bad.append(f"{folder.name}: description must be text of 1-1,024 characters (got {n})")
for line in bad:
    print(line, file=sys.stderr)
sys.exit(1 if bad else 0)
