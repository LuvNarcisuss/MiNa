-- Publish the Night Journal collection to its existing MiNa account IDs.
-- All media must already be present. Replays preserve existing rows and interactions.
begin;

do $verify$
begin
    if exists (
        select 1 from (values
    ('1614d308-7cbd-41b5-937f-a16f4614d095', 'ivy', 'Ivy Hollow'),
    ('5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'bea', 'Bea Marlow'),
    ('c8f76174-78a4-4943-88cb-5c2665679cdb', 'wren', 'Wren Vale'),
    ('a0d003a1-820b-424b-8e54-77869ea43c38', 'june', 'June Alder'),
    ('2fee4254-368a-4b4e-b62b-3c9a65c043b5', 'clea', 'Clea Fern'),
    ('924e6b2d-4130-4018-aea4-6e6dd8f99aa1', 'nell', 'Nell Rowan'),
    ('3c39c22c-45b2-4525-8f9e-a27cff669033', 'iris', 'Iris Finch'),
    ('bec894d3-db49-4419-9fb3-6ee50d094046', 'thea', 'Thea Linden')
        ) as expected(id, character, name)
        left join auth.users u on u.id = expected.id::uuid
        where u.id is null or u.is_anonymous is not true
           or (u.raw_user_meta_data ->> 'collection') is distinct from 'night-journal-v1'
           or (u.raw_user_meta_data ->> 'character') is distinct from expected.character
           or exists (select 1 from public.profiles p where lower(trim(p.name)) = lower(expected.name) and p.id <> u.id)
    ) then raise exception 'Collection identity or name mismatch.'; end if;
    if exists (
        select 1 from (values
    ('1614d308-7cbd-41b5-937f-a16f4614d095/night-journal/ivy-portrait-2.jpg'),
    ('5cf153f2-27c1-4976-ad74-f0dff4cf0667/night-journal/bea-portrait-2.jpg'),
    ('c8f76174-78a4-4943-88cb-5c2665679cdb/night-journal/wren-portrait-2.jpg'),
    ('a0d003a1-820b-424b-8e54-77869ea43c38/night-journal/june-portrait-2.jpg'),
    ('2fee4254-368a-4b4e-b62b-3c9a65c043b5/night-journal/clea-portrait-2.jpg'),
    ('924e6b2d-4130-4018-aea4-6e6dd8f99aa1/night-journal/nell-portrait-2.jpg'),
    ('3c39c22c-45b2-4525-8f9e-a27cff669033/night-journal/iris-portrait-2.jpg'),
    ('bec894d3-db49-4419-9fb3-6ee50d094046/night-journal/thea-portrait-2.jpg'),
    ('1614d308-7cbd-41b5-937f-a16f4614d095/night-journal/station.m4a'),
    ('a0d003a1-820b-424b-8e54-77869ea43c38/night-journal/rain.mp4'),
    ('5cf153f2-27c1-4976-ad74-f0dff4cf0667/night-journal/shell.m4a'),
    ('2fee4254-368a-4b4e-b62b-3c9a65c043b5/night-journal/tide.mp4'),
    ('c8f76174-78a4-4943-88cb-5c2665679cdb/night-journal/stairs.m4a'),
    ('924e6b2d-4130-4018-aea4-6e6dd8f99aa1/night-journal/moon.mp4'),
    ('3c39c22c-45b2-4525-8f9e-a27cff669033/night-journal/paper.m4a'),
    ('bec894d3-db49-4419-9fb3-6ee50d094046/night-journal/ferry.m4a')
        ) as expected(name)
        where not exists (select 1 from storage.objects o where o.bucket_id = 'mina-media' and o.name = expected.name)
    ) then raise exception 'Upload the collection media before publishing.'; end if;
end
$verify$;

insert into public.profiles (id, name, bio, avatar_path, language, allow_messages, allow_calls, show_status)
values
    ('1614d308-7cbd-41b5-937f-a16f4614d095', 'Ivy Hollow', 'Fictional character in the MiNa Night Journal. Collects the sounds between the last train and the first bird.', '1614d308-7cbd-41b5-937f-a16f4614d095/night-journal/ivy-portrait-2.jpg', 'English', false, false, false),
    ('5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'Bea Marlow', 'Fictional character in the MiNa Night Journal. Keeps a little notebook of things the sea leaves behind.', '5cf153f2-27c1-4976-ad74-f0dff4cf0667/night-journal/bea-portrait-2.jpg', 'English', false, false, false),
    ('c8f76174-78a4-4943-88cb-5c2665679cdb', 'Wren Vale', 'Fictional character in the MiNa Night Journal. Finds a tune in anything that rings.', 'c8f76174-78a4-4943-88cb-5c2665679cdb/night-journal/wren-portrait-2.jpg', 'English', true, false, false),
    ('a0d003a1-820b-424b-8e54-77869ea43c38', 'June Alder', 'Fictional character in the MiNa Night Journal. Likes rain on glass and the last window still lit on a street.', 'a0d003a1-820b-424b-8e54-77869ea43c38/night-journal/june-portrait-2.jpg', 'English', false, false, false),
    ('2fee4254-368a-4b4e-b62b-3c9a65c043b5', 'Clea Fern', 'Fictional character in the MiNa Night Journal. Leaves little coast walks here for anyone far from the water.', '2fee4254-368a-4b4e-b62b-3c9a65c043b5/night-journal/clea-portrait-2.jpg', 'English', false, false, false),
    ('924e6b2d-4130-4018-aea4-6e6dd8f99aa1', 'Nell Rowan', 'Fictional character in the MiNa Night Journal. Writes field notes on the way clouds cross the moon.', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1/night-journal/nell-portrait-2.jpg', 'English', false, false, false),
    ('3c39c22c-45b2-4525-8f9e-a27cff669033', 'Iris Finch', 'Fictional character in the MiNa Night Journal. Folds maps into paper boats and follows them in dreams.', '3c39c22c-45b2-4525-8f9e-a27cff669033/night-journal/iris-portrait-2.jpg', 'English', false, false, false),
    ('bec894d3-db49-4419-9fb3-6ee50d094046', 'Thea Linden', 'Fictional character in the MiNa Night Journal. Always remembers the lights from the ferry home.', 'bec894d3-db49-4419-9fb3-6ee50d094046/night-journal/thea-portrait-2.jpg', 'English', false, false, false)
on conflict do nothing;
insert into public.entries (id, owner_id, kind, caption, media_path, duration, created_at)
values
    ('837601cb-e719-5973-8201-e0635679e013', '1614d308-7cbd-41b5-937f-a16f4614d095', 'dream', 'The station with no clocks', '1614d308-7cbd-41b5-937f-a16f4614d095/night-journal/station.m4a', 16.0, '2026-11-22T12:53:00+00:00'),
    ('683bbf0c-8c67-5614-9fdf-55dd26e95f5d', 'a0d003a1-820b-424b-8e54-77869ea43c38', 'post', 'Watching the streetlights melt into the rain. Which color do you notice first?', 'a0d003a1-820b-424b-8e54-77869ea43c38/night-journal/rain.mp4', 10.46, '2026-11-22T11:46:00+00:00'),
    ('4bf5a505-f3e5-560e-9a3d-34bde2343800', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'dream', 'A shell with a front door', '5cf153f2-27c1-4976-ad74-f0dff4cf0667/night-journal/shell.m4a', 15.04, '2026-11-22T10:39:00+00:00'),
    ('d41e7768-15a3-5538-9251-b25dc225c2c9', '2fee4254-368a-4b4e-b62b-3c9a65c043b5', 'post', 'Twelve seconds at the edge of the water. The foam draws a different little map each time.', '2fee4254-368a-4b4e-b62b-3c9a65c043b5/night-journal/tide.mp4', 12.0, '2026-11-22T09:32:00+00:00'),
    ('16414d26-c591-5a22-8cad-d85b4c53bf4f', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'dream', 'The staircase played a tune', 'c8f76174-78a4-4943-88cb-5c2665679cdb/night-journal/stairs.m4a', 12.82, '2026-11-22T08:25:00+00:00'),
    ('8bd9c21d-023b-537f-920e-81a57a9ca4c4', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1', 'post', 'A cloud borrowed the moon for a moment. Watch the bright edge on the right.', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1/night-journal/moon.mp4', 12.0, '2026-11-22T07:18:00+00:00'),
    ('7c57a3a1-212b-5fe7-8a4b-fc30953f8112', '3c39c22c-45b2-4525-8f9e-a27cff669033', 'dream', 'Postcards in a paper boat', '3c39c22c-45b2-4525-8f9e-a27cff669033/night-journal/paper.m4a', 15.74, '2026-11-22T06:11:00+00:00'),
    ('9227f026-1e13-5065-82f6-077f6508fa5b', 'bec894d3-db49-4419-9fb3-6ee50d094046', 'dream', 'The ferry that carried stars', 'bec894d3-db49-4419-9fb3-6ee50d094046/night-journal/ferry.m4a', 13.3, '2026-11-22T05:04:00+00:00')
on conflict do nothing;
insert into public.entry_comments (id, entry_id, owner_id, body, created_at)
values
    ('a7f45a42-1422-5c9f-b33d-afa99d804a8d', '837601cb-e719-5973-8201-e0635679e013', 'bec894d3-db49-4419-9fb3-6ee50d094046', 'A pear instead of a departure bell. I hope that train takes the long way.', '2026-11-22T13:01:00+00:00'),
    ('729d41c5-ca48-584c-84d8-17e0563b1c71', '837601cb-e719-5973-8201-e0635679e013', '3c39c22c-45b2-4525-8f9e-a27cff669033', 'Keeping the leaf ticket is my favorite part.', '2026-11-22T13:06:00+00:00'),
    ('34fe6fc1-e300-5166-936b-fd309a8075a7', '683bbf0c-8c67-5614-9fdf-55dd26e95f5d', '1614d308-7cbd-41b5-937f-a16f4614d095', 'The little gold one that disappears behind the next drop.', '2026-11-22T11:54:00+00:00'),
    ('da9d7b8c-cc5b-5d8d-bff6-94c1482c0af4', '4bf5a505-f3e5-560e-9a3d-34bde2343800', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'Two cups on a tiny table. That detail stayed with me.', '2026-11-22T10:47:00+00:00'),
    ('b412bda6-61b8-5863-9b66-42a4ccbf5aed', '4bf5a505-f3e5-560e-9a3d-34bde2343800', '2fee4254-368a-4b4e-b62b-3c9a65c043b5', 'I would love to know what kind of tea the sea makes.', '2026-11-22T10:52:00+00:00'),
    ('ee6ae11a-fb30-5e2e-9a1e-e6b9430057ba', 'd41e7768-15a3-5538-9251-b25dc225c2c9', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'That thin bright line just before the water retreats.', '2026-11-22T09:40:00+00:00'),
    ('f4e24956-d621-5205-97c5-5bfb1aa2975e', 'd41e7768-15a3-5538-9251-b25dc225c2c9', 'bec894d3-db49-4419-9fb3-6ee50d094046', 'I watched twice for the second wave.', '2026-11-22T09:45:00+00:00'),
    ('bd89b971-8d9c-5d35-82ef-23fac1991b1a', '16414d26-c591-5a22-8cad-d85b4c53bf4f', 'a0d003a1-820b-424b-8e54-77869ea43c38', 'I can picture the bird waiting for its cue.', '2026-11-22T08:33:00+00:00'),
    ('047d3a4b-a818-5270-9fec-bb017acbe092', '8bd9c21d-023b-537f-920e-81a57a9ca4c4', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'The cloud looks like a curtain lifting.', '2026-11-22T07:26:00+00:00'),
    ('c104468f-fbee-5ef0-b75d-acf5c6d5d05f', '8bd9c21d-023b-537f-920e-81a57a9ca4c4', '3c39c22c-45b2-4525-8f9e-a27cff669033', 'The little pause before the moon comes back is lovely.', '2026-11-22T07:31:00+00:00'),
    ('aebdb3a5-aa1a-560f-b90f-09498d70ff57', '7c57a3a1-212b-5fe7-8a4b-fc30953f8112', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1', 'I would pin that postcard over my desk.', '2026-11-22T06:19:00+00:00'),
    ('0bc1a2f6-4c91-5577-aafc-88ac7e54e391', '9227f026-1e13-5065-82f6-077f6508fa5b', '1614d308-7cbd-41b5-937f-a16f4614d095', 'Just enough light for a book sounds perfect.', '2026-11-22T05:12:00+00:00'),
    ('6132339d-4716-5774-977f-029db93ed069', '9227f026-1e13-5065-82f6-077f6508fa5b', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'I am still thinking about that teacup.', '2026-11-22T05:17:00+00:00')
on conflict do nothing;
insert into public.entry_reactions (entry_id, owner_id, kind, created_at)
values
    ('837601cb-e719-5973-8201-e0635679e013', 'bec894d3-db49-4419-9fb3-6ee50d094046', 'like', '2026-11-22T13:00:00+00:00'),
    ('837601cb-e719-5973-8201-e0635679e013', '3c39c22c-45b2-4525-8f9e-a27cff669033', 'like', '2026-11-22T13:05:00+00:00'),
    ('683bbf0c-8c67-5614-9fdf-55dd26e95f5d', '1614d308-7cbd-41b5-937f-a16f4614d095', 'like', '2026-11-22T11:53:00+00:00'),
    ('683bbf0c-8c67-5614-9fdf-55dd26e95f5d', '1614d308-7cbd-41b5-937f-a16f4614d095', 'save', '2026-11-22T12:02:00+00:00'),
    ('4bf5a505-f3e5-560e-9a3d-34bde2343800', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'like', '2026-11-22T10:46:00+00:00'),
    ('4bf5a505-f3e5-560e-9a3d-34bde2343800', '2fee4254-368a-4b4e-b62b-3c9a65c043b5', 'like', '2026-11-22T10:51:00+00:00'),
    ('d41e7768-15a3-5538-9251-b25dc225c2c9', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'like', '2026-11-22T09:39:00+00:00'),
    ('d41e7768-15a3-5538-9251-b25dc225c2c9', 'bec894d3-db49-4419-9fb3-6ee50d094046', 'like', '2026-11-22T09:44:00+00:00'),
    ('d41e7768-15a3-5538-9251-b25dc225c2c9', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'save', '2026-11-22T09:48:00+00:00'),
    ('16414d26-c591-5a22-8cad-d85b4c53bf4f', 'a0d003a1-820b-424b-8e54-77869ea43c38', 'like', '2026-11-22T08:32:00+00:00'),
    ('8bd9c21d-023b-537f-920e-81a57a9ca4c4', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'like', '2026-11-22T07:25:00+00:00'),
    ('8bd9c21d-023b-537f-920e-81a57a9ca4c4', '3c39c22c-45b2-4525-8f9e-a27cff669033', 'like', '2026-11-22T07:30:00+00:00'),
    ('8bd9c21d-023b-537f-920e-81a57a9ca4c4', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'save', '2026-11-22T07:34:00+00:00'),
    ('7c57a3a1-212b-5fe7-8a4b-fc30953f8112', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1', 'like', '2026-11-22T06:18:00+00:00'),
    ('9227f026-1e13-5065-82f6-077f6508fa5b', '1614d308-7cbd-41b5-937f-a16f4614d095', 'like', '2026-11-22T05:11:00+00:00'),
    ('9227f026-1e13-5065-82f6-077f6508fa5b', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'like', '2026-11-22T05:16:00+00:00'),
    ('9227f026-1e13-5065-82f6-077f6508fa5b', '1614d308-7cbd-41b5-937f-a16f4614d095', 'save', '2026-11-22T05:20:00+00:00')
on conflict do nothing;
insert into public.rooms (id, host_id, title, topic, cover, visibility, allow_gifts, music_track, music_started_at, created_at)
values
    ('f4fa8d10-f699-50ce-9dd1-376a2697c4ee', '1614d308-7cbd-41b5-937f-a16f4614d095', 'The Last Stop', 'Night Journal · Leave a line about the quietest part of your day.', 'moon-seat', 'public', false, 'moon-seat', '2026-11-21T11:20:00+00:00', '2026-11-21T11:20:00+00:00'),
    ('b9d87e9e-2973-5b28-9354-cc575dad08bc', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'Low Tide Letters', 'Night Journal · A place to trade little notes from the shore.', 'moonlit-sea', 'public', false, 'moonlit-sea', '2026-11-21T11:28:00+00:00', '2026-11-21T11:28:00+00:00'),
    ('adbff39b-5c99-56a3-b239-56b5c38bbad4', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'The Humming Window', 'Night Journal · Share a tune, a rain sound or a bedtime ritual.', 'star-pillow', 'public', false, 'star-pillow', '2026-11-21T11:36:00+00:00', '2026-11-21T11:36:00+00:00')
on conflict do nothing;
insert into public.room_regulars (room_id, user_id)
values
    ('f4fa8d10-f699-50ce-9dd1-376a2697c4ee', '1614d308-7cbd-41b5-937f-a16f4614d095'),
    ('f4fa8d10-f699-50ce-9dd1-376a2697c4ee', 'a0d003a1-820b-424b-8e54-77869ea43c38'),
    ('f4fa8d10-f699-50ce-9dd1-376a2697c4ee', 'bec894d3-db49-4419-9fb3-6ee50d094046'),
    ('b9d87e9e-2973-5b28-9354-cc575dad08bc', '5cf153f2-27c1-4976-ad74-f0dff4cf0667'),
    ('b9d87e9e-2973-5b28-9354-cc575dad08bc', '2fee4254-368a-4b4e-b62b-3c9a65c043b5'),
    ('b9d87e9e-2973-5b28-9354-cc575dad08bc', '3c39c22c-45b2-4525-8f9e-a27cff669033'),
    ('adbff39b-5c99-56a3-b239-56b5c38bbad4', 'c8f76174-78a4-4943-88cb-5c2665679cdb'),
    ('adbff39b-5c99-56a3-b239-56b5c38bbad4', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1')
on conflict (room_id, user_id) do nothing;

insert into public.room_messages (id, room_id, owner_id, body, created_at)
values
    ('6f98af20-cd0b-586a-9070-3eb0988ac144', 'f4fa8d10-f699-50ce-9dd1-376a2697c4ee', '1614d308-7cbd-41b5-937f-a16f4614d095', 'Tonight’s prompt: what small sound tells you the day is over?', '2026-11-21T11:22:00+00:00'),
    ('7fe2632f-fd9f-5b16-ae26-d35131847267', 'f4fa8d10-f699-50ce-9dd1-376a2697c4ee', 'a0d003a1-820b-424b-8e54-77869ea43c38', 'The click when the kitchen light goes out.', '2026-11-21T11:31:00+00:00'),
    ('f6b8b95f-bdf3-57db-bab5-4cef1b67d3a8', 'f4fa8d10-f699-50ce-9dd1-376a2697c4ee', 'bec894d3-db49-4419-9fb3-6ee50d094046', 'For me it is the ferry bell carrying over the water.', '2026-11-21T11:40:00+00:00'),
    ('84f31aad-c0e6-59ac-8a0e-d1d4af7f2941', 'b9d87e9e-2973-5b28-9354-cc575dad08bc', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', 'If you could leave a note in a shell, what would it say?', '2026-11-21T11:30:00+00:00'),
    ('5098421c-9a33-532e-9973-cf0681ce8cf3', 'b9d87e9e-2973-5b28-9354-cc575dad08bc', '2fee4254-368a-4b4e-b62b-3c9a65c043b5', 'The tide will bring you another clean page.', '2026-11-21T11:39:00+00:00'),
    ('8a5464b0-27e3-5536-9ee9-878f21c1a646', 'b9d87e9e-2973-5b28-9354-cc575dad08bc', '3c39c22c-45b2-4525-8f9e-a27cff669033', 'Mine would have a tiny map folded inside.', '2026-11-21T11:48:00+00:00'),
    ('5f7251d9-2257-5036-b250-0f1e0cfcd27a', 'adbff39b-5c99-56a3-b239-56b5c38bbad4', 'c8f76174-78a4-4943-88cb-5c2665679cdb', 'One sound for a bedtime playlist: a spoon tapping the rim of a cup.', '2026-11-21T11:38:00+00:00'),
    ('d02cac4d-1aab-53a0-9d38-1c3d7fcdce87', 'adbff39b-5c99-56a3-b239-56b5c38bbad4', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1', 'A window latch, followed by the first few drops of rain.', '2026-11-21T11:47:00+00:00')
on conflict do nothing;
insert into public.follows (follower_id, followed_id, created_at)
values
    ('1614d308-7cbd-41b5-937f-a16f4614d095', 'a0d003a1-820b-424b-8e54-77869ea43c38', '2026-11-22T14:00:00+00:00'),
    ('1614d308-7cbd-41b5-937f-a16f4614d095', 'bec894d3-db49-4419-9fb3-6ee50d094046', '2026-11-22T14:01:00+00:00'),
    ('5cf153f2-27c1-4976-ad74-f0dff4cf0667', '2fee4254-368a-4b4e-b62b-3c9a65c043b5', '2026-11-22T14:03:00+00:00'),
    ('5cf153f2-27c1-4976-ad74-f0dff4cf0667', '3c39c22c-45b2-4525-8f9e-a27cff669033', '2026-11-22T14:04:00+00:00'),
    ('c8f76174-78a4-4943-88cb-5c2665679cdb', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1', '2026-11-22T14:06:00+00:00'),
    ('c8f76174-78a4-4943-88cb-5c2665679cdb', 'a0d003a1-820b-424b-8e54-77869ea43c38', '2026-11-22T14:07:00+00:00'),
    ('a0d003a1-820b-424b-8e54-77869ea43c38', '1614d308-7cbd-41b5-937f-a16f4614d095', '2026-11-22T14:09:00+00:00'),
    ('a0d003a1-820b-424b-8e54-77869ea43c38', 'c8f76174-78a4-4943-88cb-5c2665679cdb', '2026-11-22T14:10:00+00:00'),
    ('2fee4254-368a-4b4e-b62b-3c9a65c043b5', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', '2026-11-22T14:12:00+00:00'),
    ('2fee4254-368a-4b4e-b62b-3c9a65c043b5', 'bec894d3-db49-4419-9fb3-6ee50d094046', '2026-11-22T14:13:00+00:00'),
    ('924e6b2d-4130-4018-aea4-6e6dd8f99aa1', 'c8f76174-78a4-4943-88cb-5c2665679cdb', '2026-11-22T14:15:00+00:00'),
    ('924e6b2d-4130-4018-aea4-6e6dd8f99aa1', '3c39c22c-45b2-4525-8f9e-a27cff669033', '2026-11-22T14:16:00+00:00'),
    ('3c39c22c-45b2-4525-8f9e-a27cff669033', '5cf153f2-27c1-4976-ad74-f0dff4cf0667', '2026-11-22T14:18:00+00:00'),
    ('3c39c22c-45b2-4525-8f9e-a27cff669033', '924e6b2d-4130-4018-aea4-6e6dd8f99aa1', '2026-11-22T14:19:00+00:00'),
    ('bec894d3-db49-4419-9fb3-6ee50d094046', '1614d308-7cbd-41b5-937f-a16f4614d095', '2026-11-22T14:21:00+00:00'),
    ('bec894d3-db49-4419-9fb3-6ee50d094046', '2fee4254-368a-4b4e-b62b-3c9a65c043b5', '2026-11-22T14:22:00+00:00')
on conflict do nothing;

commit;
