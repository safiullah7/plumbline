#!/usr/bin/env bash
# Shared eval fixture for v0.4b: FieldLog, a Flutter app for field technicians
# (surface mobile-ui). Module "jobs" with one planned feature, 01-offline-notes:
# a spec and acceptance criteria written, nothing else. Sourcing this file
# scaffolds the repo and leaves one commit on main. Cases add what they test (the
# test plan, ux.md, the QA report); $F is the feature folder:
#   source "$(dirname "$0")/../_fixture/flutter.sh"
# The feature docs come from the plugin's own kickoff.sh and templates.
set -e
source "$(dirname "${BASH_SOURCE[0]}")/profile.sh"

git init -q -b main
git config user.name eval
git config user.email eval@example.com
git config core.autocrlf false
mkdir -p lib/jobs test integration_test

project_profile no none "| mobile-ui | Flutter | lib/** test/** integration_test/** pubspec.yaml | flutter run -d emulator-5554 | flutter analyze | dart format --set-exit-if-changed . | generic |" '### mobile-ui
```
flutter test --name "{ids_regex}"
```'

new_feature jobs offline-notes standard mobile-ui
F=$FEATURE

cat > docs/product/jobs/vision.md <<'EOT'
# Jobs vision

Owner: product engineer

## Who it's for
Field technicians who visit customers' sites with a phone, often in basements
and plant rooms with no signal. A technician has 6-10 jobs a day.

## Problem
Technicians write notes on paper or in a notes app and retype them later, so
notes are lost, late or wrong.

## Product principles
- Never lose typed data, with or without a network.
- One hand, gloves on: big targets, no precision gestures.
- The next job is always one tap away.

## Features
Each feature is named by the outcome it changes for a user. Folder:
docs/product/jobs/. The job list shipped before Plumbline.
| Feature | Goal | Outcome (measurable) | Why next | Status |
| --- | --- | --- | --- | --- |
| 01-offline-notes | Technicians keep notes on a job without a network | 95% of notes written offline reach the server within a day | Lost notes are the top support complaint | Planned |
EOT

cat > "$F/spec.md" <<'EOT'
# Feature 01: Offline job notes

Owner: product engineer

## Goal
A technician can add a note to a job at any time, with or without a network.
Notes written offline are saved on the phone and sent when the network returns.

## Requirements
| Priority | Requirement | Use case |
| --- | --- | --- |
| P0 | Add a text note to a job from the job screen | UC-01-01 |
| P0 | A note written offline is kept on the phone and shown as "Not sent yet" | UC-01-02 |
| P0 | Unsent notes are sent automatically when the network returns | UC-01-02 |
| P1 | The technician can add a photo to a note; the app asks for camera permission when first needed | UC-01-03 |

## Business rules
- A note is 1-2000 characters. Photos are at most 5 per note.
- Notes are never deleted from the phone before the server confirms them.
- If the server rejects a note, it stays on the phone marked "Couldn't send" with a Retry button.

## Data and permissions
Notes belong to the signed-in technician and to one job. The camera is the only
permission the app asks for. Without it, the note can still be written.

## Non-Goals
Editing or deleting notes after they are sent. Notes on several jobs at once.

## Success metrics
| Metric | Target | Measured how, over what window |
| --- | --- | --- |
| Notes written offline that reach the server | 95% within 24 hours | Server logs, first 4 weeks |
EOT

cat > "$F/acceptance-criteria.md" <<'EOT'
# Feature 01 acceptance criteria

Owner: product engineer. Every criterion is observable on the device and states
the exact expected result. Tests are named after these IDs. Priority matches the
requirement's priority in spec.md (P0, P1, P2).

| ID | Use case | Given | When | Then | Priority |
| --- | --- | --- | --- | --- | --- |
| AC-01-001 | UC-01-01 | a technician on the Job screen with a network | they type "Replaced filter" and tap Save note | the note appears at the top of the Notes list with the time and no badge | P0 |
| AC-01-002 | UC-01-01 | a technician on the Job screen | they type 2001 characters | Save note is disabled and the counter reads "2001/2000" in red | P0 |
| AC-01-003 | UC-01-02 | the phone is in airplane mode | they save the note "Boiler off" | the note appears with the badge "Not sent yet" and survives closing and reopening the app | P0 |
| AC-01-004 | UC-01-02 | one note is "Not sent yet" | the network returns | within 30 seconds the badge disappears | P0 |
| AC-01-005 | UC-01-02 | the server rejects a note | the app tries to send it | the note shows "Couldn't send" with a Retry button, and the text is kept | P0 |
| AC-01-006 | UC-01-03 | camera permission was never asked | the technician taps Add photo | the system permission dialog appears; if they deny it, the note stays writable and a hint says "Photos need camera access" | P1 |
EOT

cat > pubspec.yaml <<'EOT'
name: fieldlog
description: Job notes for field technicians.
publish_to: none
version: 0.3.0+7

environment:
  sdk: ">=3.4.0 <4.0.0"

dependencies:
  flutter:
    sdk: flutter
  http: ^1.2.0
  shared_preferences: ^2.2.0

dev_dependencies:
  flutter_test:
    sdk: flutter
  integration_test:
    sdk: flutter
  flutter_lints: ^4.0.0

flutter:
  uses-material-design: true
EOT

cat > lib/main.dart <<'EOT'
import 'package:flutter/material.dart';

import 'jobs/jobs_screen.dart';

void main() => runApp(const FieldLogApp());

class FieldLogApp extends StatelessWidget {
  const FieldLogApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FieldLog',
      theme: ThemeData(colorSchemeSeed: const Color(0xFF1B5E20), useMaterial3: true),
      home: const JobsScreen(),
    );
  }
}
EOT

cat > lib/jobs/job.dart <<'EOT'
enum JobStatus { scheduled, inProgress, done }

class Job {
  const Job({required this.id, required this.title, required this.address, this.status = JobStatus.scheduled});

  final String id;
  final String title;
  final String address;
  final JobStatus status;
}
EOT

cat > lib/jobs/jobs_repository.dart <<'EOT'
import 'job.dart';

/// Today's jobs for the signed-in technician. The demo repository is in memory.
class JobsRepository {
  Future<List<Job>> today() async => const [
        Job(id: 'j1', title: 'Boiler service', address: '12 Mill Lane', status: JobStatus.inProgress),
        Job(id: 'j2', title: 'Replace thermostat', address: '4 Quay Street'),
      ];
}
EOT

cat > lib/jobs/jobs_screen.dart <<'EOT'
import 'package:flutter/material.dart';

import 'job.dart';
import 'jobs_repository.dart';

/// The home screen: today's jobs, in visit order.
class JobsScreen extends StatelessWidget {
  const JobsScreen({super.key, this.repository});

  final JobsRepository? repository;

  @override
  Widget build(BuildContext context) {
    final repo = repository ?? JobsRepository();
    return Scaffold(
      appBar: AppBar(title: const Text("Today's jobs")),
      body: FutureBuilder<List<Job>>(
        future: repo.today(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final jobs = snapshot.data ?? const <Job>[];
          if (jobs.isEmpty) return const Center(child: Text('No jobs today'));
          return ListView(
            children: [
              for (final job in jobs)
                ListTile(
                  title: Text(job.title),
                  subtitle: Text(job.address),
                  trailing: job.status == JobStatus.inProgress ? const Chip(label: Text('In progress')) : null,
                ),
            ],
          );
        },
      ),
    );
  }
}
EOT

cat > test/jobs_screen_test.dart <<'EOT'
import 'package:fieldlog/jobs/jobs_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows the jobs for today', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: JobsScreen()));
    await tester.pumpAndSettle();
    expect(find.text('Boiler service'), findsOneWidget);
    expect(find.text('Replace thermostat'), findsOneWidget);
  });
}
EOT

cat > integration_test/jobs_flow_test.dart <<'EOT'
import 'package:fieldlog/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('the app opens on the jobs list', (tester) async {
    await tester.pumpWidget(const FieldLogApp());
    await tester.pumpAndSettle();
    expect(find.text("Today's jobs"), findsOneWidget);
  });
}
EOT

git add -A
git commit -qm "FieldLog app with the planned offline-notes feature"
