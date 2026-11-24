# MiNa functional and visual review

November 24, 2026. Xcode 26.3 (17C529), Debug, iPhone 17 Pro running iOS 26.3, MiNa QA, device DBFA7AD1-FB00-4FB8-8287-D8E72FE9594E. The app was rebuilt from the existing working tree at base commit 02a3513, installed over the existing QA installation and operated through its normal UI with the supplied password account. The account displayed the name Night Listener. The test used the company service and the standard MiNa scheme. No product code or design source was changed.

## Findings

| Priority | Reproduction | Observed outcome |
| --- | --- | --- |
| High | Open Feed and play a Night Journal video. Open Dream Space and try a Night Journal recording. | The app reports “Object not found.” Using the signed-in account and the same signing request as the app returned HTTP 400 for all three editorial videos, five narrated dreams and eight portraits. A video uploaded during this run returned HTTP 200 and opened in the native player. These results establish what a member can access. Missing objects and unreadable objects require operator-side investigation to distinguish. |
| High | Open June Alder’s rain video, choose More options, report with reason Other, and acknowledge the receipt. Return to Feed and reopen the post. | Receipt 8e0d3672 was displayed. The post remained visible in Details, Feed, a caption search and the author profile. The report explicitly identified an editorial QA exercise. |
| High | From that detail page, open June’s profile, choose More, Block listener, and confirm. | Details showed “Content unavailable.” The app stayed on the detail page, with no originating-tab return or block-success alert. After cold launch and fresh login, the feed omitted the author and Blocked users showed June by name. |
| High | Unblock June in Profile and return to the recommended feed. | One tap immediately removed the block, without a separate confirmation. The still-reported video reappeared and opened. Profile contains a block list but no report history or withdrawal action. The second undo order cannot be completed through the UI. |
| Medium | Open a post’s discussion and inspect the available actions for an existing comment. | The author opens a profile. The comment only presents its text. Source inspection confirms there is no reply-to-comment, comment-level report or direct block menu. Flat text and emoji comments successfully survived re-entry. |
| Medium | Open Messages with no prior conversations. Follow June, enter her thread from Messages and inspect the composer. | The initial inbox displayed “No conversations yet” with no people-discovery button. In the followed character’s thread, the input, Send and Voice call were disabled, but the page still invited the user to start a conversation without explaining the recipient’s restriction. The character’s profile also disabled Chat. All eight fictional editorial characters have private messaging and calls turned off in their published configuration. A nickname search for QA returned no results. |
| Medium | With microphone permission initially undecided, open Dream Space, Record a dream, and tap to record. Choose Allow in the system dialog. | The recorder stayed at 0:00 and instructed the user to grant permission in Settings. A second tap started recording and the counter reached 0:02. DeviceMedia uses the same error for denied permission and an inactive app at the moment of the permission callback. Stopping the take on this simulator returned “No sound was captured.” Recovery returned the recorder to its initial state. Publishing stayed disabled. |
| Medium | Open the gift drawer in an active room. | The review button extended to approximately y=878 on an 874-point screen. The home indicator crossed the button near its bottom edge. |
| Low | Open Profile and follow the row labeled “Privacy agreement” in the artwork. | The row leads to Privacy settings. Agreement and settings are separate destinations in the product design. Its accessibility label already says “Privacy settings.” |
| Low | Start an AI session and read the exchange. | The app displayed the response and remaining session time, but the two chat bubbles lacked individual message timestamps called for in the product design. |
| Medium | Publish a video and a dream under the test account, delete each through its own My Posts or My Dreams confirmation, then read back the records and try signing those two exact media paths as their owner. | Both entry records disappeared and both source objects still returned HTTP 200 signed links. The tested delete operation only deletes the entry row. Both QA objects were removed separately with the account’s ordinary Storage permission. Their signing requests then returned HTTP 400. Access by other people after deletion was not tested. |

## What the run exercised

- **Authentication.** The welcome screen gated Sign in until credentials and consent were present. Both policy readers opened and returned. The supplied account reached Rooms. Relaunch prompted for credentials again as specified by the project. A fresh sign-in reopened the same account and block list. Sign out returned to entry, a malformed email kept the button disabled, and a final sign-in reached Rooms again.
- **Publishing and discussion.** A project-owned twelve-second moon video was imported through Photos and published with an English caption. My Posts displayed the entry. Its native video player opened. Both a text comment and a moon emoji reappeared after leaving and reopening the detail. Like and unlike were exercised.
- **AI Companion.** The center tab, Sleep Tips, About, the sharing confirmation and the free sixty-minute session were exercised. The prompt received a generated reply. All three illustrated topic sheets opened and closed. The timer and send state changed. The same exchange was present after a fresh login.
- **Rooms.** An empty title raised a validation message. An Only me room opened with the test account as host, one member and the mic off. A room message reappeared with the sender and time. The audience, invite, microphone, gift and music panels opened. The selected music showed Stop and Mute room music. Daily check-in changed to Checked in today and disabled the button. The ranking period and category changed. The host canceled the exit prompt once, then ended the room. A second local-only room draft retained its title and selected cover when reopened for editing.
- **Dreams.** Recording permission, retry, timer, stop, silence rejection, recovery and blocked empty submission were exercised. To test playback independently of the microphone, the same account used the normal media and entry endpoints to upload the project’s 15.998-second station narration as a new QA dream. Upload returned 200, creation returned 201, and readback matched. In Dream Space the elapsed time advanced, pause worked and save/unsave changed state. My Dreams showed the item and its owner deletion removed it. This evidence does not establish successful microphone-to-publish on a physical phone.
- **Room listener.** Searching for Low Tide returned the matching room. It opened with the host away and earlier conversation marked as such. The room report sheet and host-block confirmation opened and were canceled. Requesting seat 2 showed queue position 1. Canceling restored the request action. The audience panel opened. Offline search also found Starlight Lullaby. Play/pause and save/unsave were exercised.
- **Personal settings.** Allow messages was switched off, the page was closed and reopened to verify the saved setting, then the original on state was restored. The blocked user remained identifiable after a cold launch. Profile editing opened and saved the existing values. Following June incremented her follower count and unfollowing restored it. People search returned June by name. Messages, recent calls and all three notification categories opened. The support form prevented empty submission. Community Guidelines, account deletion and sign-out confirmation pages opened. Irreversible account deletion was left at Cancel.
- **Wallet.** The account balance displayed zero. All seven pack buttons were disabled with “No packages are available in this storefront.” Wallet activity, level, catalog and backpack opened. Selecting Triple Six showed a 29-coin cost and an insufficient-balance message. Open wallet and Back returned to the same selected gift. Claiming one free Sleep Mask added one unit to the backpack. No real charge was initiated.

## Visual interpretation

The app uses the approved star field, mint gradients, room artwork, AI robot, store grid and purple wallet coin. Differences in branding, credential fields, real balances, real occupancy, the free AI session, missing timed promotions, and the 16:9 post detail video follow the current product specification. The most disruptive visual loss is the missing remote artwork and media. Feed cards show black error panels, dreams lose their waveform controls, and the public profile loses its full-height portrait. The room gift drawer and Profile settings label have separate issues described above.

## Moderation history

The checked-in database migrations give the actor a report receipt and leave a report row. The block list represents current blocks, and the app deletes the block row on unblock. The reviewed migrations contain no separate durable record for a withdrawn block. Private operator history, operator access and external delivery were not verified with staff credentials. No moderation action against the target was claimed.

## Evidence

Each panel pairs the supplied design on the left with a screenshot from this run on the right. The 26 pairs cover product surfaces. Source boards also include alternate overlays, graphic sheets and icon assets.

- [Welcome, Rooms, Feed and Messages](comparison-01.jpg)
- [Profile, AI Companion, AI chat and post creation](comparison-02.jpg)
- [Post discussion, wallet, blocked users and room creation](comparison-03.jpg)
- [Live stage, gift drawer, Dream Space and recorder](comparison-04.jpg)
- [Profile editing, rankings, store and private chat](comparison-05.jpg)
- [Public profile, room search, notifications and level](comparison-06.jpg)
- [Music drawer and privacy settings](comparison-07.jpg)
- [Report receipt, block destination and persisted block list](safety-observations.jpg)
- [Editorial media, a new upload and first microphone permission](media-and-recording.jpg)

The gift drawer’s review action and the edit profile Save control both cross the home-indicator area on their initial screens. Scrolling allowed Save to be used. The AI response also rendered its two ending emoji as boxed glyphs on this simulator.

## Scope and account effects

The QA post, its comments and the QA dream were removed. The two resulting media objects were separately cleaned up and rechecked. The temporary follow, block, like, save and privacy changes were reversed. The account retains the explicitly marked editorial QA report, its AI conversation and session, the closed private room with a chat message and check-in, and the free Sleep Mask. The private room draft is saved on the QA installation, and the project-owned moon clip remains in the QA simulator photo library.

Private message transmission, counterpart receipt, a connected two-person call, live microphone audio between phones, a second person accepting an invite or approving a seat, and gift delivery to an active recipient remain unverified. The supplied account and the fictional characters permitted testing the messaging restriction, inbox, history screens and room or AI chat. The tested app exposes no report withdrawal, so the reverse undo order is unavailable. Operator processing, a physical microphone-to-publish run, VoiceOver, enlarged text, offline cold launch, support-ticket delivery and permanent account erasure were not accepted in this run.

## Execution and payment evidence

XCTest completed one interactive application journey in 955.610 seconds. Each screen or operation above was evaluated using its captured accessibility state, screenshot or corresponding service response. Exploratory actions that initially failed to reach a control were revisited when possible. The XCTest result alone does not establish feature acceptance. A separate evidence check matched 33 expected observations against the captured UI state.

Two initial local StoreKit harness attempts failed before a transaction was created. The simulator’s storekitd log identified the isolated host as not installed for development. After the temporary host was rebuilt with its Debug development entitlement, one separate XCTest case passed and verified a distinct local test transaction for each of the seven project product IDs. It removed the transactions created by that case. The production MiNa project, account balance and Apple storefront configuration were unchanged. This exercised the local catalog fixture and transaction creation. The native purchase dialog, MiNa receipt delivery, cancellation, deferred payment, duplicate credit, Apple sandbox and production payment remain unverified.
