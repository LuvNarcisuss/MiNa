# Night Journal

Night Journal is an editorial collection for MiNa's rooms, Dream Square and video feed. Each illustrated identity is a fictional character. Each profile discloses that role in its bio and uses a different stock photograph. Public chat, comments, likes and follows in this collection connect only the listed characters. The rooms use the existing MiNa tracks for optional listening. A host can be away. Room presence and microphone seats still come from connected clients.

## Media and sources

The source links and individual photographer credits are in [the collection](collection.json). The eight portraits are 512-pixel square crops, inspected in the circular layout used by the app. The three H.264 videos are twelve-second silent excerpts of actual footage of waves on a shore, lights through a rainy window and clouds crossing the moon. The delivered cuts were reviewed at one, five and ten seconds. Photos and footage are used under the [Pexels license](https://www.pexels.com/license/). Character names and biographies are original fiction. The people pictured are stock models.

The five dream entries contain original English stories. Each has a separate AAC narration, approximately 13–16 seconds long. The collection uses a shared editorial narrator. The narration was synthesized offline using the [LJ Speech Piper voice](https://huggingface.co/rhasspy/piper-voices/tree/main/en/en_US/ljspeech/medium), based on the [public-domain LJ Speech dataset](https://keithito.com/LJ-Speech-Dataset/). Transcripts are included in the collection file.

## Cloud records

The app reads the collection from company project `weieitgfketnpvvwvfpa`. The original publication used migration source `nojpfyqctfwdshqnzudp`. [Account IDs](accounts.json) bind characters to the anonymous Auth identities created for this collection. The private `mina-media` bucket stores portraits, videos and recordings at `<account-id>/night-journal/<filename>`. The app uses authenticated feed, profile and signed media requests.

The [publication transaction](publish.sql) checks the account bindings, display name collisions and presence of all media before inserting rows. Stable IDs and conflict handling support replays without duplicate entries or social interactions. Run it only against the named project after uploading the media. The collection grants no coins or purchased items. New listeners start with their own inbox, follows and bookmarks.

## Original publication

Authenticated API readback returned eight distinct profiles, three public rooms, eight room notes, five narrated dreams, three video posts, thirteen comments, thirteen likes and sixteen follow relationships. The database contained four saved entries among the collection accounts. No collection account occupied a room seat or appeared on a room roster. Each of the sixteen media files was downloaded using a different account from its owner; its bytes matched the local asset. All eight publishing sessions were signed out. This verification used the hosted API and did not run the iOS app.

The refreshed eight portraits use individual crops and versioned object names. A single transaction updated only the eight existing avatar references. Authenticated signed downloads of all eight files matched the SHA-256 values in the collection. The temporary upload policy and publishing account were removed.

## Company storage verification on November 24, 2026

The company database held all sixteen media references and lacked all sixteen Storage objects. The restoration uploaded the original three videos, five recordings and eight portraits at their existing paths. The server checked the file size and SHA-256 of each upload before writing it. The bucket remains private. The temporary upload function now returns HTTP 410 and contains no upload code.

The signed-in QA member downloaded eight portraits, five recordings and the moon and tide videos. Each of the fifteen downloaded files matched its local SHA-256. The member's existing report on the rain video prevented a fresh signed URL, as expected. The rain upload passed the same server-side hash check as the other fifteen. Storage metadata confirmed all sixteen objects after restoration.
