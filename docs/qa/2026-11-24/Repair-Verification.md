# MiNa repair verification

November 24, 2026. This report follows the [original review](QA-Review.md). The Debug build used Xcode 26.3, the standard MiNa scheme and the company backend. The app was installed over the existing installation on MiNa QA, an iPhone 17 Pro running iOS 26.3 (DBFA7AD1-FB00-4FB8-8287-D8E72FE9594E). The same password account performed the member actions.

## Media and moderation

| Scenario | Observed result |
| --- | --- |
| Restore editorial media | All three videos, five narrations and eight portraits were restored at their original private paths. The server checked all sixteen original hashes during upload. The member downloaded fifteen accessible objects and their bytes matched the originals. The account's previously reported rain video remained inaccessible to this member. |
| Delete a published video or narration | The member uploaded both types, confirmed they were readable and removed them. The final entry reads were empty and both new signing requests returned HTTP 400. An interrupted deletion could be retried. Removing one of two entries sharing the same source retained the file for the surviving entry. |
| Reply and report a comment | A reply read back with its exact parent ID. Submitting a report twice with the same operation ID produced one receipt. Only the targeted comment disappeared. The post and the reply remained readable. Withdrawing restored the comment. The temporary reply was removed. |
| Report and block the same author | Both undo orders were exercised through the authenticated service. After the first undo, direct entry, feed and caption-search reads still excluded the post. After both undos all three reads restored it. The block list retained the author's name. The earlier rain-video report remained active. |
| Block from a profile opened from Feed | The app returned to the selected Feed tab. The refreshed feed excluded the author, and the dismissible alert named Clea Fern. Dismissing the alert left the filtered feed visible. |
| Manage safety in Profile | The simulator displayed the comment's report receipt and the reported text in Report history. Canceling unblock left the member blocked. Confirming the next unblock removed the member. A separate withdrawal confirmation updated the report to Withdrawn. |
| Operator history | An operator read confirmed report, withdrawal, block and unblock events after the corresponding active state had been reversed. The authenticated and anonymous roles have no SELECT privilege on the private audit table. |

The [media restoration record](../../../supabase/collections/night-journal/README.md) and [backend delivery notes](../../Delivery.md) provide additional detail. No external operator notification or review decision was part of this run.

A second block journey started from Find people in Messages. After confirmation, the selected Messages root showed the empty inbox and a single success alert naming June Alder. Unblocking kept her earlier video report in force. On the final build the first captured return frame after a new video report and the following settled feed both excluded the video. Withdrawal restored it.

## Recording, navigation and layout

- The simulator's microphone permission was reset. After one tap on Record and one tap on the native Allow button, the timer reached 0:02 and Stop recording appeared. Stopping rejected the silent simulator input. A restored editorial dream independently played to 0:03 and paused.
- The empty inbox offered Find people. Searching from that button opened the matching editorial profile.
- On the first Edit profile screen, the rendered Save capsule sat entirely above the home indicator. Tapping without scrolling saved the existing values and returned to Profile. The visible Privacy settings row opened the privacy switches.
- The room gift drawer opened in Low Tide Letters. Its Review gift control occupied y=786–832 on the 874-point screen, leaving the home-indicator region clear. This room had no eligible recipient for a gift.
- June Alder's conversation explicitly displayed that the listener had turned off both private messages and voice calls. Send was disabled. The temporary follow used to reach the conversation was reversed.
- The live AI service answered the new prompt. The two message bubbles showed their own timestamps and retained them after reopening. Older messages displayed Time unavailable because the original records did not include a time.
- Screenshot inspection caught replacement boxes even when the simulator returned a valid color-font glyph. On the final build, both the earlier herb and sparkles and the new leaf and sparkles appeared as colored symbols, with the original message text preserved for accessibility and storage.

## Visual evidence

- [Original boards and the corrected gift and Save controls](repair-layout.jpg)
- [Video playback, the refreshed Feed block alert and first microphone permission](repair-community.jpg)
- [Empty inbox, recipient restrictions and corrected AI timestamps and symbols](repair-messages.jpg)

## Publishing regression found during retest

The earlier successful post had left a draft pointing to a removed device file. The revised composer preserves its caption, clears the unavailable attachment, explains the problem and disables Publish until a video is selected again. After importing the twelve-second moon clip from the simulator photo library, the app published the video with the preserved caption. A text comment and its nested reply survived closing and reopening Details. Deleting in My Posts emptied the list. A separate owner-session read found neither the entry nor a newly signable source object. Reopening New post showed an empty draft with Publish disabled.

## Coverage and account state

The two deployed company migrations are [member safety and replies](../../../supabase/migrations/20261124071734_member_safety_and_replies.sql) and [entry media deletion](../../../supabase/migrations/20261124072059_delete_entry_media.sql). Install the updated app for the new deletion flow. Earlier clients that issue a direct entry-row DELETE need this update. This delivery covers the QA installation and company backend.

All temporary follows and blocks were reversed. The member had zero follows, zero blocks and one active report, the original rain-video report. The newly created QA video, its discussion and its source file were removed. New withdrawn receipts remain in safety history. The AI exchange remains in the account's local history. The simulator microphone permission is now granted.

The exploratory XCTest sessions encountered a native iOS Save Password prompt intercepting taps, the stale composer attachment, an abbreviated text-field value in the UI hierarchy and a photo-picker tap made while the system sheet was still loading. The affected flows were rerun using the visible picker and captured UI states. Twenty-six separate evidence assertions passed. The layout and rendered glyphs also received screenshot inspection. After dismissing the system prompt, a separate final XCTest on the installed candidate passed in 29.831 seconds with one case and zero failures. It asserted signed-in Feed visibility, an empty and disabled composer, inbox discovery, and timestamped AI history after relaunch.

Two-way calls and message receipt, physical microphone-to-publish, delivery to an active gift recipient, and Apple sandbox or production transactions require separate acceptance. The original review records the earlier local StoreKit test. No purchase or App Store release was performed in this repair run.


## Follow-up on the comment emoji picker

A member screenshot showed all six quick reactions as missing glyphs in the comment palette. The earlier AI bubble check did not exercise these buttons. The updated app uses a bundled color font for the quick reactions in the picker, the editable text and the saved discussion. On MiNa QA, one XCTest opened Nell Rowan's moon video, tapped every reaction, verified the exact Unicode draft, sent it and reopened the post. Screenshot inspection confirmed all six colored glyphs in the palette, draft and posted comment. The member's exact new test comment was removed after verification. [Comment picker and filled draft](comment-emoji-picker.png)
