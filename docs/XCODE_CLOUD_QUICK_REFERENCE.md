# Xcode Cloud Quick Reference — lsom

## Workflows

| Workflow | Trigger | What it does |
|---|---|---|
| **Build (Debug)** | Every push (all branches) | Compiles the project |
| **Test** | Every push (all branches) | Runs the test suite |
| **Release** | Tag `v*.*.*` | Archive + sign + notarize |

## Release a New Version

```bash
# 1. Tag the release
git tag v1.0.0

# 2. Push the tag (triggers Release workflow)
git push origin v1.0.0
```

## Common Tag Commands

```bash
# Tag with message
git tag -a v1.0.0 -m "Release 1.0.0"
git push origin v1.0.0

# List tags
git tag

# Delete a tag (local + remote)
git tag -d v1.0.0 && git push origin --delete v1.0.0
```

## Monitor Builds

- **Web:** [developer.apple.com](https://developer.apple.com) → Xcode Cloud
- **Xcode:** Report Navigator (⌘9) → Cloud tab

## Key Details

- **Team ID:** `DW97QZ7F3B`
- **Scheme:** `lsom`
- **Repo:** `mikezamayias/budget-coach`

## Quick Troubleshooting

| Problem | Fix |
|---|---|
| Scheme not found | Ensure scheme is **Shared** in Xcode → Manage Schemes |
| Build fails | Check logs in Xcode Cloud dashboard |
| Notarization stuck | Wait — Xcode Cloud retries automatically |
| GitHub not connected | Check GitHub Settings → Integrations → Xcode Cloud app |

---

*See [XCODE_CLOUD_SETUP_DETAILED.md](./XCODE_CLOUD_SETUP_DETAILED.md) for the full guide.*
