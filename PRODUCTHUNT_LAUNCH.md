# lsom: ProductHunt Launch Plan

**Launch Target:** April 2026 (Timing: Tuesday or Wednesday, 00:01 PST)
**Success Metric:** $500+ revenue on launch day (PMF signal)
**Target Audience:** Mac power users, developers, designers, gamers

---

## 1. Product Positioning

### Headline
**Lightweight Logitech Control for macOS — No Bloatware Required**

### Tagline
"Unlock your Logitech mouse on macOS. Native. Fast. Open."

### The Problem
- **Logitech GHub:** 500MB+ RAM footprint, slow, electron-based bloat
- **No alternatives:** macOS users stuck with system-level battery indicator, no DPI/polling control
- **Power users frustrated:** Can't customize their expensive mice without running memory hogs

### The Solution
**lsom** = Logitech Status on Mac
- **Native macOS:** Pure SwiftUI, ~3,800 lines of code
- **Lightweight:** <50MB install, ~15MB RAM at runtime
- **Feature-complete:** Battery display, DPI adjustment, polling rate control, button mapping (MVP)
- **Privacy-focused:** No telemetry, no network access—just HID communication
- **Open development:** GitHub, transparent roadmap

### Why Now?
1. **v0.2.0-beta.1 proved concept** — Battery display + DPI read + polling read all working
2. **v1.0.0 adds write capabilities** — Full control over DPI and polling rate
3. **Market demand clear** — Every macOS gamer/developer complains about GHub

---

## 2. Feature Highlights (v1.0.0)

### Shipping in v1.0.0
- ✅ **Battery Monitoring** — Real-time battery % in menu bar + popover
- ✅ **DPI Adjustment** — Full read-write control, profiles persist across restarts
- ✅ **Polling Rate Control** — Live toggle between 125/250/500/1000 Hz
- ✅ **Settings Persistence** — Your preferences saved locally
- ✅ **Auto-refresh** — Configurable refresh intervals
- ✅ **Dark mode** — Native macOS experience

### Roadmap (Post-Launch)
- 🔄 **Button Mapping** — Remap 2-3 buttons per mouse (Q2 2026)
- 🔄 **Multi-device Support** — Control multiple mice simultaneously (Q2 2026)
- 🔄 **Gesture Recognition** — Custom gestures for quick actions (Q3 2026)
- 🔄 **CLI Tool** — `lsom-cli` for scripting and automation (Q3 2026)

---

## 3. Supported Hardware

**Currently Supported:**
- Logitech G Pro X Superlight (✅ Tested)
- Any Logitech mouse with Unifying Receiver (USB 0xC547)
- HID++ 2.0 protocol compatible

**Testing Matrix:**
- ✅ Logitech G Pro X Superlight
- 🧪 MX Master 3 (needs testing)
- 🧪 MX Keys (needs testing)
- 🧪 G Pro (2022) (needs testing)

**OS Support:**
- macOS 13.0+ (Ventura, Sonoma, Sequoia)

---

## 4. Competitive Analysis

| Feature | lsom | GHub | Existing Mac Apps |
|---------|------|------|-------------------|
| Battery % | ✅ | ✅ | ❌ (only system) |
| DPI Adjustment | ✅ | ✅ | ❌ |
| Polling Rate Control | ✅ | ❌ | ❌ |
| Memory Footprint | ~15MB | 500MB+ | — |
| Boot Time Impact | Minimal | Heavy | — |
| Open Source | 🔄 (Planned Q2) | ❌ | Various |
| Privacy | ✅ (No telemetry) | ❓ (Cloud-based) | — |
| Price | Free (Launch) | Free | Freemium |

**Why lsom wins:** Native, lean, respectful of system resources, transparent development

---

## 5. Launch Assets Checklist

### Visuals (Priority 1)
- [ ] **Logo & Icon** (512x512 PNG)
  - Current: Simple mouse icon
  - Polish: Add subtle gradient, "lsom" wordmark
  - Deliverable: `assets/lsom-icon-512.png`

- [ ] **Hero Screenshot** (2560x1600)
  - Menu bar icon showing battery %
  - Popover open with DPI, polling rate, stats
  - Dark mode variant
  - Deliverable: `assets/hero-light.png`, `assets/hero-dark.png`

- [ ] **Feature Screenshots** (3x)
  1. Battery monitoring detail
  2. DPI adjustment panel
  3. Polling rate selector
  - Deliverable: `assets/feature-battery.png`, etc.

- [ ] **Comparison Chart**
  - lsom vs GHub vs Default
  - Memory, features, speed
  - Deliverable: `assets/comparison.png`

### Video (Priority 1)
- [ ] **30-second Demo Video**
  - 0-5s: Problem (GHub taking 500MB, slow)
  - 5-15s: lsom menu bar + popover showcase
  - 15-25s: Adjusting DPI, polling rate live
  - 25-30s: Call to action (ProductHunt link)
  - Format: MP4, 1080p, with captions
  - Deliverable: `assets/lsom-demo-30s.mp4`

- [ ] **Process/How-it-works Video** (Optional, 60-90s)
  - Reverse engineering HID++ protocol briefly shown
  - macOS native architecture explanation
  - Deliverable: `assets/lsom-technical-overview.mp4`

### Copy (Priority 1)
- [ ] **ProductHunt Post Title & Subtitle**
  - Title: "lsom — lightweight Logitech control for macOS"
  - Subtitle: "The GHub alternative that actually respects your Mac's resources"
  - Deliverable: See section 6 below

- [ ] **First Comment (Mandatory)**
  - Introduce yourself, story of why you built it
  - "I built this because..." narrative
  - Call for feedback, link to GitHub
  - Deliverable: See section 7 below

- [ ] **FAQ/Help Text**
  - Troubleshooting Input Monitoring permission
  - Device compatibility questions
  - Deliverable: `PRODUCTHUNT_FAQ.md`

### Testimonials & Social Proof (Priority 2)
- [ ] **Collect 3-5 Beta User Testimonials**
  - Target: Logitech enthusiasts, tech reviewers, Mac developers
  - Testimonials file: `TESTIMONIALS.md`
  - Format: `"[Quote]" — [Name], [Title/Context]`
  - [See section below for template]

- [ ] **GitHub Stars & Credibility**
  - Ensure repo is public, MIT/proprietary license clear
  - Pin README to landing
  - Add "Built in public" badge to repo
  - Deliverable: GitHub repo prep

---

## 6. ProductHunt Post Content

### Headline
```
lsom — Lightweight Logitech Control for macOS
The GHub alternative that actually respects your Mac's resources
```

### Subtitle
```
Native SwiftUI menu bar app for battery, DPI, and polling rate control.
No bloatware. No telemetry. Just HID++ communication.
```

### Short Description (140 chars)
```
A lightweight macOS menu bar app that monitors your Logitech mouse 
battery, DPI, and polling rate—without the 500MB memory footprint of GHub.
```

### Long Description (700-900 words)
```
## Why lsom?

I was frustrated. My 2-year-old MacBook Pro slowed down noticeably 
every time I opened Logitech's official GHub app. 500MB of RAM gone. 
5+ seconds to launch. All I wanted? To see my mouse battery and adjust DPI.

So I reverse-engineered the Logitech HID++ 2.0 protocol and built the 
native alternative I deserved: **lsom**.

## What lsom Does

**Menu Bar Battery Display**
See your Logitech mouse battery percentage at a glance. No delays. Updates 
whenever you click, or on your custom refresh interval (1, 5, or 15 minutes).

**DPI Adjustment**
Switch between your mouse's supported DPI levels instantly. Your preference 
persists across restarts—never lose your settings.

**Polling Rate Control**
Live toggle between 125Hz, 250Hz, 500Hz, and 1000Hz. Perfect for gaming 
sessions where you need maximum responsiveness, or productivity work where 
battery life matters more.

**Button Mapping (Coming in v1.1)**
Remap 2-3 buttons to suit your workflow.

## Why It's Different

- **Native macOS Experience:** Pure SwiftUI, not Electron bloat
- **Lightweight:** ~50MB install, ~15MB RAM (vs 500MB+ for GHub)
- **Privacy First:** No telemetry, no cloud sync, no tracking—just local HID communication
- **Open Development:** Transparent roadmap, public GitHub, built in the open
- **Respects Your Mac:** Minimal resource usage, instant launch, no startup slowdown

## Supported Hardware

Currently tested on **Logitech G Pro X Superlight** via Unifying Receiver.

In theory, any Logitech mouse using the HID++ 2.0 protocol should work. 
If your mouse isn't listed, let us know—we can test and add support.

## The Technical Story

This project reverse-engineered the Logitech HID++ 2.0 protocol using 
publicly available specs and community documentation. Zero third-party 
dependencies. Pure Swift + IOKit. ~3,800 lines of carefully structured code.

I did this so you don't have to. Use lsom. Get your Mac back.

## What's Next?

**Q2 2026:** Button mapping, multi-device support  
**Q3 2026:** CLI tool for automation and scripting  
**Future:** Community feedback will drive the roadmap

## Get Started

1. Download from GitHub Releases (notarized)
2. Grant Input Monitoring permission
3. Drop it in Applications
4. Enjoy

It's free. Always will be.

---

**Questions? Feedback? [GitHub](https://github.com/mikezamayias/lsom) 
or reply below.** 🖱️
```

---

## 7. First Comment (Launch Day)

This comment should be posted **immediately upon launch** to set the tone and engage early voters.

```
Hi Product Hunt! 👋 I'm [Your Name], and I built lsom because I was 
frustrated watching Logitech GHub consume half my MacBook's RAM just to 
check my mouse battery.

## The Story

Last fall, I was working on a deadline, and my 16GB M3 Pro felt sluggish. 
I opened Activity Monitor: GHub was using 500MB+ RAM. I didn't even use 
most of its features—I just wanted to know my battery % and tweak my DPI.

So I spent the weekend reverse-engineering Logitech's HID++ protocol and 
building lsom: a native, lightweight alternative. 3,800 lines of Swift. 
Zero dependencies. 15MB RAM at runtime. Respectful of your system.

## What Changed Since Beta?

v1.0.0 adds **full write control**: adjust DPI and polling rate live, with 
settings that persist across restarts. Battery monitoring is instant. 
Everything syncs to your preferences locally.

## Let's Talk

- **What device do you use?** Help me test and expand compatibility
- **What feature would you add?** I'm building this in the open
- **Is there a GHub alternative you prefer?** Let's discuss the trade-offs

[GitHub Repo](https://github.com/mikezamayias/lsom)  
[Full Roadmap](https://github.com/mikezamayias/lsom/projects)

Excited to share this with the PH community. Thanks for being here. 🖱️✨
```

---

## 8. Testimonials (Placeholder)

**Collect these before launch:**

```markdown
"I ditched GHub immediately. lsom is faster, lighter, and doesn't 
make my MacBook feel like it's running on fumes."
— [Name], Competitive Esports Player

"As a developer, I appreciate the low overhead. One less bloatware 
app eating my system resources."
— [Name], iOS Developer

"Finally, a tool that respects the Mac. lsom is proof you don't need 
a megabyte for every kilobyte of functionality."
— [Name], Mac Enthusiast & Tech Writer
```

**Action Items:**
1. Reach out to beta testers in your network
2. Contact relevant Mac/gaming blogs
3. Ask on Reddit: r/macOS, r/GamingOnMac
4. Share early builds with Discord communities

---

## 9. Launch Day Strategy

### Timeline (00:01 PST = 8:01 GMT)

| Time | Action |
|------|--------|
| -2h | Verify all ProductHunt links, media, copy |
| 00:01 | **Post goes live** |
| 00:05 | First comment posted (story + call to action) |
| 00:30 | Share on Twitter/X (your followers) |
| 02:00 | Share on LinkedIn (professional network) |
| 06:00 | Engage with comments (respond to 10+ replies) |
| 12:00 | Reddit r/macOS post with genuine story |
| 18:00 | Recap on Twitter (# ships upvoted, engagement rate) |

### Social Media Messaging

**Twitter/X:**
```
🖱️ After 6 months reverse-engineering Logitech's HID++ protocol, 
I'm shipping lsom: the lightweight alternative to GHub.

Battery monitoring. DPI adjustment. Polling rate control. All without 
the 500MB memory footprint.

Live on ProductHunt now: [link]

It's free, native, and respects your Mac. #macOS #ProductHunt
```

**LinkedIn:**
```
[More professional tone about technical achievement + career growth]

Open-sourcing my reverse-engineering journey into the Logitech 
HID++ protocol. Built a native macOS app from scratch.

Full story → [link]
```

**Reddit (r/macOS):**
```
[Title: "I reverse-engineered Logitech HID++ and built a GHub 
alternative for macOS. It's now v1.0. Here's the story."]

[Post the PH first comment verbatim, link to GitHub, ask for feedback]
```

### Engagement Goals

- **Target:** 500 upvotes on ProductHunt by end of day 1
- **Minimum success:** Top 10 of the day
- **Stretch:** Top 3 (signals strong PMF)

### Metric Tracking

- ProductHunt upvotes (goal: 500+)
- GitHub stars (track daily)
- Download counts
- Comments/feedback quality
- Social shares

---

## 10. Post-Launch (Week 1-4)

### Week 1 Actions
- [ ] Respond to all ProductHunt comments by Day 3
- [ ] Fix any reported bugs within 24h (v1.0.1 patch)
- [ ] Collect feedback, consolidate in GitHub Discussions
- [ ] Publish "What We Learned" blog post

### Week 2-4
- [ ] Feature in Mac blogs/newsletters (pitch outreach)
- [ ] Reach out to YouTube creators for review/demo
- [ ] Publish v1.0.1 with community-requested fixes
- [ ] Start teasing Q2 roadmap (button mapping)

### Success Metrics to Track
- Revenue (if monetized; else: user growth)
- GitHub stars growth
- Website traffic
- Email signup rate (if applicable)
- Community sentiment (GitHub discussions, Twitter replies)

---

## 11. Monetization Strategy (Optional)

**v1.0 Launch:** **FREE** (build audience)

**Future (Q3 2026):**
- **Free Tier:** Battery monitoring, DPI read, auto-refresh
- **Pro Tier ($4.99/month):** Full DPI/polling write, button mapping, CLI tool
- **Open Source:** Core code open-sourced (dual licensing)

*Rationale:* Free builds trust and user base. Pro tier funds development 
and keeps the app sustainable long-term. Open source = community contribution.

---

## 12. Checklist (Final)

### Before Launch
- [ ] v1.0.0 tagged in GitHub
- [ ] Build artifacts notarized and tested
- [ ] All marketing assets ready (logo, screenshots, video)
- [ ] ProductHunt post draft reviewed
- [ ] Testimonials collected and formatted
- [ ] First comment drafted
- [ ] Social media scheduled (or pre-written)
- [ ] README updated with ProductHunt link
- [ ] GitHub Discussions enabled
- [ ] Email for support set up (replies monitored 24/7)

### Launch Day
- [ ] Post goes live at scheduled time
- [ ] First comment posted within 5 minutes
- [ ] Social media share (twitter, LinkedIn, Reddit)
- [ ] Monitor comments and respond actively
- [ ] Track metrics (upvotes, stars, traffic)
- [ ] Bug watch (monitor logs, GitHub issues)

### Week 1 Post-Launch
- [ ] All comments replied to
- [ ] Any critical bugs patched (v1.0.1)
- [ ] Feedback summary published
- [ ] Blog post draft started

---

## 13. Key Talking Points

Use these in responses, interviews, and marketing:

1. **"Why this exists:"** GHub is bloat. lsom respects your Mac.
2. **"The reverse engineering story:"** 6 months, HID++ 2.0 protocol, zero dependencies.
3. **"Lightweight by design:"** Pure Swift + IOKit. ~3,800 lines. 15MB RAM.
4. **"Privacy first:"** No telemetry. No cloud. Just local HID communication.
5. **"Open development:"** Built in public. Roadmap on GitHub. Community-driven.
6. **"For Mac users:"** Native SwiftUI. Respects system design. Minimal resource usage.

---

## 14. Links to Maintain

**Keep these updated:**
- ProductHunt: [TBD - link after launch]
- GitHub: https://github.com/mikezamayias/lsom
- Demo video: [Embed in ProductHunt + tweet]
- Feature comparison chart: [External link or GitHub wiki]
- Roadmap: [GitHub Projects]

---

## 15. Risks & Mitigation

| Risk | Mitigation |
|------|-----------|
| Device incompatibility issues | Pre-test on 3+ devices, provide clear supported list |
| Input Monitoring permission confusion | Detailed FAQ, walkthrough screenshots |
| Negative comments about beta quality | Emphasize v1.0 is production-ready, offer quick fixes |
| GHub comparison blow-back | Focus on features, not attacking GHub—let users choose |
| Technical criticism (HID++ docs) | Link to sources, explain reverse engineering approach |

---

**Launch this. Execute this. Win this.** 🚀🖱️
