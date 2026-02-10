# lsom Beta Recruitment Strategy

## Goal

Recruit 50-100 beta testers for v0.2.0-beta.1 across HN, Reddit, and Twitter.

**Timeline:** February 10-25, 2026  
**Target Release:** GitHub Releases (v0.2.0-beta.1)

---

## Target Audience

### Primary
- **Mac power users** - Developers, designers, content creators
- **Logitech mouse users** - G Pro X, MX Master, etc.
- **Reddit communities:** r/macsetups, r/mechanicalkeyboards, r/logitech

### Secondary
- **Tech enthusiasts** - HN audience
- **Twitter indie hacker community** - #indiehackers #buildinpublic

### Tertiary
- **GitHub watchers** - Project followers who'll see release notification

---

## Recruitment Channels

### 1. Hacker News (Show HN Post)

**Timing:** Monday morning, 8-9 AM EST (better engagement)  
**URL:** https://github.com/mikezamayias/lsom  

**Title:**
```
Show HN: lsom – Native macOS menu bar app for Logitech mouse battery & DPI
```

**Post Body:**
```
Hi HN,

I've built lsom, a native macOS app that solves a problem I had: my Logitech mice on Mac had zero battery visibility, no DPI control, and no polling rate adjustment.

It's a minimal SwiftUI + IOKit menu bar app that:
- Shows battery % in your menu bar in real-time
- Reads/adjusts DPI on-the-fly (for supported mice)
- Controls polling rate (125Hz-1000Hz)
- ~3,800 lines of Swift, no third-party dependencies

Built on HID++ 2.0 protocol (used by competitors with USB drivers) but fully native—no kernel extensions or system hacks.

I'm looking for beta testers with Logitech Unifying Receivers. Currently supports:
- Logitech G Pro X Superlight
- MX Master 3
- MX Anywhere (likely)
- Other HID++ 2.0 mice

The app is free in beta. Looking to collect feedback on:
- Device compatibility
- UI/UX
- Feature requests

GitHub: https://github.com/mikezamayias/lsom
Beta download: https://github.com/mikezamayias/lsom/releases/tag/v0.2.0-beta.1

Open to feedback and contributions!
```

---

### 2. Reddit Posts

#### r/macsetups

**Title:**
```
[BETA] lsom – Battery & DPI control for Logitech mice in your menu bar
```

**Body:**
```
Hey r/macsetups!

I've been frustrated with my Logitech mouse on macOS—no battery display, no DPI control, nothing. So I built lsom.

It's a native menu bar app that shows:
- Real-time battery percentage
- Current DPI & polling rate
- Full DPI/polling control

It uses IOKit + HID++ 2.0 protocol (same tech competitors use but ours is native, no drivers needed).

**Currently looking for beta testers!** If you have a Logitech mouse with a Unifying Receiver, I'd love your feedback.

Download: https://github.com/mikezamayias/lsom/releases/tag/v0.2.0-beta.1

Issues? Feature ideas? Comments? Drop them in the GitHub issues or reply here!
```

#### r/logitech

**Title:**
```
[BETA] lsom – Free macOS app for Logitech mouse battery & advanced controls
```

**Body:**
```
Hi r/logitech!

Built a native macOS app for Logitech mice that adds features the official Mac drivers don't have:

✨ **What it does:**
- Live battery indicator in menu bar (color-coded: green/yellow/red)
- View & change DPI on the fly
- Control polling rate
- Auto-refresh (every 5 sec - 15 min, configurable)
- Zero telemetry, 100% local

🎯 **Supports:**
- Logitech G Pro X Superlight
- MX Master 3
- MX Anywhere
- Any Logitech HID++ 2.0 mouse with Unifying Receiver

🚀 **Beta Status:**
- Free during beta
- Future: $29/month Pro tier for advanced features
- All current features free forever

**Need your feedback!** Testing Logitech mice, DPI changes, polling rate reliability.

Download: https://github.com/mikezamayias/lsom/releases/tag/v0.2.0-beta.1

GitHub: https://github.com/mikezamayias/lsom

Thanks!
```

#### r/mechanicalkeyboards (optional, for mouse+keyboard desk setup builders)

**Title:**
```
[BETA] lsom – Battery display for Logitech mice in your macOS menu bar
```

**Body:**
```
Hey r/mechanicalkeyboards!

Not strictly keyboard content, but if you're a mechanical keyboard enthusiast, chances are your mouse/peripherals matter too.

Just shipped lsom for macOS—adds battery display and DPI/polling controls to your Logitech mouse. Free beta, looking for testers.

https://github.com/mikezamayias/lsom

Feedback welcome!
```

---

### 3. Twitter/X Posts

#### Main Announcement

```
🎉 lsom beta is live! Native macOS menu bar app for your Logitech mouse.

✨ Battery % in menu bar
✨ Real-time DPI control  
✨ Polling rate adjustment
✨ Zero telemetry, built with IOKit + Swift

Free to test. Feedback welcome!

🔗 https://github.com/mikezamayias/lsom/releases/tag/v0.2.0-beta.1

#macOS #indiedev #logitech
```

#### Indie Hacker Reply Thread

Reply to indie dev/maker tweets with:
```
Hey! Just shipped lsom—a native macOS app for Logitech mice (battery display, DPI control, polling rate).

Building in public, looking for beta testers. Free to try:
https://github.com/mikezamayias/lsom

Would love your feedback if you use Logitech on Mac!

#indiedev #buildinpublic
```

#### Retweet/Like Strategy

- Follow #indiedev, #buildinpublic, #macOS tags
- Like & reply to relevant tweets from makers/designers
- Engage authentically (not spammy)

---

## Beta Feedback & Collection

### GitHub Issues Template

Create issue template for beta feedback:

```markdown
# Bug Report / Feature Feedback

**System:**
- macOS Version: [e.g., Ventura 13.2]
- Logitech Mouse Model: [e.g., G Pro X Superlight]

**What happened:**
[Describe the issue or feedback]

**Expected behavior:**
[What should happen]

**Steps to reproduce:**
1. [Step 1]
2. [Step 2]

**Screenshots:**
[Attach if applicable]

**Logs:**
[Paste any error messages]
```

### Discord/Slack (Optional)

If getting 20+ testers, consider:
- Create Discord server for real-time feedback
- Daily standup channel
- Feature request voting
- Bug triage

---

## Timeline

| Date | Action |
|------|--------|
| Feb 10 | Release v0.2.0-beta.1 (workflow) |
| Feb 11 | HN submission (Show HN) |
| Feb 12 | Reddit posts (r/macsetups, r/logitech) |
| Feb 13-14 | Twitter threads & engagement |
| Feb 15-25 | Monitor feedback, bug fixes |
| Feb 26+ | Address critical issues, prepare v0.2.1 patch |

---

## Success Metrics

- **Signups:** 50-100 beta testers
- **GitHub Issues:** 10-20 feedback items
- **Engagement:** 15+ comments per post
- **Retention:** 30%+ of testers continue through v1.0

---

## Copy/Paste Templates

### Email to Friends/Colleagues

```
Subject: Beta testing: lsom – Logitech mouse app for Mac

Hey!

I've been building lsom, a native macOS app for Logitech mice. 

If you use a Logitech mouse with a Unifying Receiver on Mac, I'd love your feedback on the beta.

It shows battery %, DPI, polling rate—basically everything missing from Logitech's Mac drivers.

Try it: https://github.com/mikezamayias/lsom/releases/tag/v0.2.0-beta.1

Feedback: Create a GitHub issue or reply to this email.

Thanks!
```

### GitHub Discussions Post (if enabled)

```
# v0.2.0-beta.1 Feedback Thread

Welcome to the beta! 

Please share:
- ✅ What works great
- ❌ Bugs you found
- 💡 Feature ideas
- 🤔 Questions

All feedback helps shape the roadmap.

Thanks for testing!
```

---

## Notes for Main Agent

This recruitment push should land 50-100 testers by end of February. Track metrics:
- GitHub stars/watchers
- Issues created
- Release download count
- Retention to v1.0

Results inform ProductHunt positioning for April launch.
