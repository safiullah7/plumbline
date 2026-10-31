---
description: Triage splits a whole-module request with several journeys into ordered slices with a Split line, and keeps Size Full for the whole request.
tags: [skill, build, triage, v0.6]
model: sonnet
max_turns: 15
timeout_seconds: 600
allowed_tools: [Read, Glob, Grep, Agent, Skill, Write, Edit]
---

/plumbline:build Build a complete patient billing module for the clinic app. Staff create invoices with line items and taxes, view and filter an invoice list, take payments by card, cash or bank transfer including part payments, issue refunds with a reason and an approval step, print patient statements for any date range, and send automatic payment reminders by email and SMS on a schedule. Admins manage price lists and tax rates, and everything is audited.

Stop as soon as you have shown the triage block. Don't create files or start the work, and don't ask me anything first.
