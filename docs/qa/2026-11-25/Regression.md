# MiNa regression review · November 25, 2026

The app was built from revision `dd6c033` and installed on the MiNa QA iPhone 17 Pro simulator running iOS 26.3. UI checks used the supplied QA account. Service checks used the same company Supabase project as the app and isolated members for two-account tests. StoreKit Test used an isolated app identity and the current wallet implementation to keep test coins out of the supplied account.

## Findings

| Finding | Evidence | Impact |
| --- | --- | --- |
| The previous purchase verifier is still deployed. | The active `wallet-purchase` v2 code verifies with Apple and calls `credit_coin_purchase`. The replacement handler in the repository returns HTTP 410. | The current iOS checkout grants local credit without this endpoint. Earlier clients still have a backend purchase path. |
| Device-funded gift fulfillment is missing from the company deployment. | The client calls `gift-spend`. The deployed function list has no entry for it, and a database lookup of `public.resolve_device_gift(uuid)` returned no function. | A shared gift funded by local coins, or a purchase that needs both local and server coins, cannot complete its normal settlement. This is separate from StoreKit checkout. No production coins were spent. |
| Checkout still showed “Waiting for purchase approval.” after Ask to Buy was declined in StoreKit Test. | The isolated wallet first received a deferred transaction. After the test store declined it, the wallet was still busy at the end of a 12.5-second observation. The persisted balance stayed at 112,700 and there were still seven credits. | Purchase buttons remained disabled during the observation. Later automatic recovery and behavior in the Apple sandbox were not established. |

## Assets and publication

| Check | Result |
| --- | --- |
| Public app assets | All eight objects in `mina-art` were downloaded and matched the SHA-256 hashes of a fresh export from this revision. They total 8,126,195 bytes. The interface package contains 506 WebP slices, the font and policies. The other objects cover the sound library, three WAV files, icon, launch art and attribution. The three room covers resolve to library entries. |
| Private media inventory | All 16 distinct entry and avatar references resolved to `mina-media`. The bucket contained eight JPEG portraits, five M4A recordings and three MP4 videos. An independent signed-in account downloaded each object by signed URL and matched the source hashes. |
| Video published in the app | Through New post → Files, the QA account selected a 12-second MP4 and published it. The returned entry pointed to an owner-scoped object. A fresh signed download contained 495,267 bytes and matched the selected file, SHA-256 `605409234aff527e5143fe511eb57a6d07023dddc73f3d59a0abdb5722da49e6`. The QA post and object were then removed through the normal deletion flow. |
| Other uploaded media | A new M4A dream and a second MP4 were uploaded, published and downloaded through the authenticated app services. Both matched the input bytes. Removing one of two references preserved the shared M4A. Repeated deletion completed cleanly, with the last reference and object gone. An isolated member also uploaded an avatar, changed its profile and read the JPEG back. |
| Dream recorder | A fresh account started and stopped a recording on MiNa QA. The simulator supplied silence. MiNa rejected the recording with its native microphone alert. The successful dream upload above used a known audible M4A. Successful capture and publication from a physical microphone remain unverified. |

The application icon and launch resources also ship in the iOS bundle. The app stages captures on the device during upload. The private purchase ledger and AI conversation history are device data.

## Safety

- Reporting a comment hid that comment for the reporter. Its parent post and a test reply stayed visible. Retrying with the same report ID produced one receipt. Withdrawal restored the comment.
- Reporting a video and blocking its author were tested in both undo orders. The feed, search and direct entry read excluded the video while either restriction remained. Withdrawing the report and lifting the block restored the eligible item.
- A saved entry disappeared from the reporter's saved results, remained hidden after a new sign-in and returned after withdrawal. The second member retained access throughout.
- Blocking an existing chat contact removed friendship eligibility and hid that conversation. In the feed detail UI, blocking Clea Fern returned to the feed, removed the post and showed one dismissible success alert. A second account could still see the post. The QA account's block was then removed.
- The operator history retained report, withdrawal, block and unblock events. Public and authenticated client roles had no read grant on that history. The room report and host-block confirmation screens were also opened and canceled. Moderation staff response, external notifications and every possible navigation origin were outside the observed results.

## Other feature coverage

| Area | Observed behavior |
| --- | --- |
| Accounts and profiles | Sign-in succeeded. The registration form showed errors for invalid email and password confirmation. Isolated account registration, bootstrap, profile editing and deletion succeeded. The supplied account's deletion confirmation was canceled. |
| Community | Like and save toggled successfully. The six comment reactions inserted into the draft. A separate service test created a threaded reply and read back its parent. |
| Rooms | A private room was created and closed. Room chat, check-in and ranking queries completed. The UI opened a public room, past messages, the report flow and the gift catalog. |
| Private messages and calls | A message sent by the supplied account appeared in the second member's inbox. Marking it read cleared the unread count. The conversation row exposed pin, unread and delete on a left swipe. Pin and read state toggled, and canceling deletion preserved the row. Recent calls and the three notification categories opened. Voice and video previews were exercised. The speaker switched without requesting microphone access. Enabling the microphone invoked permission, including the Settings recovery after denial. Call invitation, acceptance and ending were verified at the signaling layer. |
| AI Companion | A new prompt reached the live `companion-chat` Edge Function after consent. Its deployed code calls the Groq chat completions API. The UI received replies, including the requested word “Moonbeam”, and reopened the conversation. Canceling the first consent prompt preserved the unsent text. |
| Discovery and listening | Sleep Tips, Emotion and Life Advice opened and dismissed. The rankings and recommended rooms screens opened. A soundscape started from its listening page and paused through its playback control. |
| Profile destinations | Blocked users, Report history, Privacy settings, Terms of use, My level, Store & backpack, Contact us, Community guidelines and Delete account each opened their expected destination. |

## Purchases

The seven product IDs in the StoreKit configuration are consumables. The iOS code fetches products with `SKProductsRequest`, buys through `SKPaymentQueue` and handles transactions with `SKPaymentTransactionObserver`. Receipt verification and the account-specific Keychain credit happen on the device. The transaction is finished after the credit is persisted.

All seven packs credited the isolated wallet in Xcode StoreKit Test. The observed cumulative balances were 400, 1,200, 3,650, 8,800, 19,600, 49,000 and 112,700. Redelivery and ledger reload preserved seven credit records. The company purchase table contained zero entries when checked.

An injected store failure granted no coins. The simulator mapped the attempted cancellation injection to a store error, so that run does not establish the wording after a person cancels an Apple purchase sheet. The independent Ask to Buy decline test failed its final checkout-availability assertion as recorded above.

App Store Connect product activation, an Apple sandbox or production charge, production App Attest and physical-device camera, microphone and two-way media quality require separate device or store evidence. No production payment or deployment change was made.


## Follow-up · direct gift delivery

Later the same day, the old purchase Edge Function was deleted and its URL returned HTTP 404. A separate migration to remove the historical SQL credit function was declined. The new authenticated gift delivery RPC was deployed and the iOS app installed on MiNa QA. The function handles real room gift receipts with the existing account session. It has no Apple team configuration or attestation key dependency.

An isolated Xcode StoreKit Test purchase credited 400 coins. Two gifts at 29 coins reduced the balance to 342. Repeating the operation left one receipt visible to the recipient. Reusing the operation with a different funding source was rejected. A 29-coin backpack purchase and its subsequent delivery left 313 coins. Insufficient funds and disabled room gifts produced no lasting charge. The final regression passed with zero failures and the two temporary test users were removed. No Apple sandbox or production purchase was submitted.

## Room gift button

On MiNa QA (iPhone 17 Pro, iOS 26.3), the previous build showed a full-color, disabled Review gift button in The Humming Window. The room had one present listener and its saved gift setting was off.

The updated build passed two UI tests. The same room displayed a disabled Room gifts are off control. In a separate room accepting gifts, Invite a friend opened the friend list. A second account joined while the drawer was open, and the sender could immediately review one Star Friend priced at 59 coins. When the recipient left, the confirmation closed and the balance remained at 1600 coins. The test stopped before sending. A database read confirmed the original room setting and zero remaining temporary accounts or rooms for these tests.

## Homepage pull-to-refresh

The current app was installed on MiNa QA (iPhone 17 Pro, iOS 26.3). One UI test pulled down three times on Voice Rooms and three times on Recommended Feed. Both the Hot Rooms and Recommended sections changed their first card on each room pull. The feed changed its first card after each pull, including a journal reading in the rotation. The room sections kept their leading cards after a 21-second wait, and the feed kept its leading card after 47 seconds, spanning their regular 20- and 45-second synchronization intervals.

A separate Swift check exercised 500 shuffles across lists of 0, 1, 2, 3 and 30 cards. It checked membership, leading-card changes, stable ordering on reload, pagination, removals and overlapping requests.
