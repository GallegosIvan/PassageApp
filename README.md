# Passage — Bible Study & Church Community

<p align="center">
  <img src="assets/icon/icon.png" width="120" alt="Passage App Icon" />
</p>

<p align="center">
  <strong>Study together. Grow together.</strong>
</p>

<p align="center">
  A Bible study app built for your faith community.
</p>

---

## Features

**📖 Bible Reader**
Read Scripture in over 200 translations including the KJV, BSB, WEB, ASV, and more. Highlight verses, add personal notes, bookmark chapters, and track your reading progress with daily streaks and a full reading history calendar.

**🤖 AI Bible Assistant**
Ask anything about Scripture and get instant, thoughtful answers grounded in the Bible. Use your voice to study hands-free. The AI assistant helps you understand passages, explore biblical history, and deepen your faith — available anytime.

**🧠 Bible Quizzes**
Test your knowledge of any chapter with AI-generated comprehension quizzes tailored to the specific passage you're studying.

**⛪ Churches**
Join your church privately by scanning a QR code in person — no public search, no open invites. Inside your church you'll find group chats, Bible study communities, and announcements from your leadership.

**🌐 Bible Study Communities**
Join public Bible study communities organized by book and chapter. Share interpretations, reply to others, and grow through real discussion with fellow believers.

**✨ Passage Pro**
Expanded AI usage, unlimited conversation history, more daily quizzes, private study communities, and the ability to create up to 3 churches. 7-day free trial — cancel anytime.

---

## Tech Stack

- **Flutter** — cross-platform iOS & Android
- **Supabase** — database, auth, realtime, edge functions
- **RevenueCat** — subscription management
- **Claude Haiku (Anthropic)** — AI Bible assistant & quiz generation
- **Resend** — transactional email via `mail.biblepassage.app`

---

## Architecture Highlights

- Row-level security on all Supabase tables — users can only access their own data
- All user display data served via `get_public_profiles` SECURITY DEFINER RPC — no direct `users` table access
- Subscription sync handled server-side via Edge Function calling RevenueCat's API — clients never write subscription state directly
- Three-strike moderation system with one-appeal-per-lifetime enforcement, all RPC-backed
- Church joins are QR-only and enforced server-side via `follow_church` RPC
- Terms of service re-prompting handled automatically via timestamp comparison — no manual version bumping

---

## Status

🚧 Currently in pre-launch — App Store submission in progress.

---

## Contact

**Ivan Gallegos** — [biblepassageapp@gmail.com](mailto:biblepassageapp@gmail.com)