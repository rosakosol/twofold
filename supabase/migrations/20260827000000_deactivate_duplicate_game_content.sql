-- Deactivates near-duplicate rows found by a full-content audit (2,122 active rows
-- checked across all 4 game-content tables, ~12.5% redundancy) -- most of it from the same
-- fact/prompt being independently rewritten across separate seed batches over time, not caught
-- by simple text matching (trivia dupes were mostly found by cross-checking shared
-- correct_answer values, since the wording itself often differs completely).
--
-- Soft-deactivated (active = false), not deleted -- these rows may still be referenced by
-- game_session_rounds.content_id on already-completed sessions, and deleting them outright
-- would break re-opening those sessions' history. Deactivating removes them from future
-- sessions while leaving past ones intact, and is trivially reversible if any of these turn out
-- to be judgment calls worth revisiting.
--
-- One row from each duplicate group is kept active. Where content was judged genuinely
-- equivalent ("either" in the audit), one was picked to remove arbitrarily but consistently.
-- 5 additional trivia pairs flagged in the audit as "moderate confidence" (same subject, less
-- clearly redundant -- e.g. two different Cold War definitions) are deliberately NOT included
-- here; they're closer calls best made by a human reading them, not this migration.

-- trivia_questions: 54 rows across 52 duplicate groups (1 exact duplicate + 51 near-duplicates)
update public.trivia_questions
set active = false
where id in (
  '5c3d79f2-7035-4d37-b430-5fe8c09c0775',
  'a33bc001-dd3c-4714-9eaf-29057dc59847',
  '283813c6-2804-4c0e-9e17-537bde943928',
  '60ed52e4-af05-4ac7-aa14-57e5ca1da2ea',
  '09034633-6523-45cc-bc09-b17cae7bc6af',
  '2382285f-7e96-4a9b-986a-4b48b07747ff',
  '167ca0ec-53b1-4a67-a500-a341c3f78dee',
  'c949a318-7a2b-4b0e-ad66-54692b4d2efd',
  '775e1ea6-8214-4498-871f-d7684b47cb70',
  '6042064a-ace6-44e8-a7f9-348f98484f39',
  '038d45e4-7cb9-4787-be46-54ab5128953b',
  'a884f9f4-0828-4211-95cf-def21dcb71d7',
  '81b92682-82d4-41ba-8b33-1ab74d69689b',
  '55adeccd-ed24-428b-a70d-f157eb08fb3e',
  '74624917-bf06-42d6-b75a-7963a5ad0908',
  '11fd881c-d6b2-4ca5-b0b1-8e4be769c588',
  '521d9713-406f-4da1-bc45-48dc11f3cb66',
  '9c455a37-0b5a-4a43-9cbc-c90f923611bf',
  '3b7fb1bb-e126-437c-895c-a176d7317417',
  '93eb4459-510c-4a68-9a3a-acef74200f09',
  '20fc7aed-b471-4b7d-adb7-e17ca727d8cc',
  '0ec8b327-8d80-448d-96fa-48178e501dca',
  '09b05c53-4bf8-42ba-bdc2-ec8a3da508e6',
  '7865e6a9-68e8-4b6f-83a3-6765c4ad0101',
  '4447b941-ad8d-4ea0-b622-8f62f2c3b7a7',
  '0f85029c-6195-4ec6-a798-fb929ba5403a',
  'dd9fc046-f617-4ee9-94e2-a1f20275d1fb',
  'ba6abbbb-493f-4811-b5a6-034eb6ef58bb',
  '17524242-4ef1-4334-92c1-e6e2256067a4',
  '9e2bb05b-5754-4b53-9672-75773a2cbb1a',
  '6fa26d31-ad8a-4380-96d9-1a4236e75f1a',
  'e3fcd0c6-154f-41b1-abc8-68ff10e20208',
  '873b0f5b-e872-4ef4-b86e-62ea2e2da2bd',
  '6e15d407-fd7e-423c-a4ec-60304ab4a1b4',
  'a00f10d2-7b9e-40e7-9e44-81c957358326',
  '0e5d4616-9ed8-4374-bb48-53d86e22c934',
  '60f51595-ce16-4302-824e-02516396945e',
  '243ca8b3-ea86-4cc8-8688-ea75a025282a',
  '45755f3b-c1dd-4d86-86a7-9703fa7eabc8',
  '4ebda7a2-853a-4e96-922c-5dd824c44661',
  'cdcad403-a7ca-4042-8698-84eaac75c997',
  '9c6fda0f-aa2f-43cd-8718-acb19579609c',
  'aec305e5-90f9-4e6a-bf10-705ff3adc52c',
  '0f212a22-7aa6-4b9a-acd2-4ef6b930e9df',
  '7cd9c0e7-4bd1-494d-a1e2-cd4e8e9a5123',
  '1cc84d9b-7ad8-4f91-9dc3-cf846fa52198',
  '10095e17-d1ef-4ae9-918e-255dcc252aee',
  '62da897c-5293-468a-8ad0-31b6afc8e438',
  '1b66afa8-2c8d-4d27-b0af-e7436db88599',
  '402915ad-87c8-41e5-9826-947c7ca83518',
  '274fe7f2-0599-4ed0-a48e-e287d72a913d',
  '637ae595-8183-4b2a-85d1-aa9997bd9063',
  '8ae21136-bedc-4bae-a1b0-1d3f2490d937',
  '637a8f03-09f9-4469-b8dd-40faed74a141'
);

-- more_likely_prompts: 24 rows across 23 duplicate groups
update public.more_likely_prompts
set active = false
where id in (
  '7509145b-3aca-4d03-9306-faef9fb8da11',
  'a31389f1-81df-4e60-9912-3dd8d64f15b6',
  '43a39b79-c5d2-4e4f-bf66-42e4f50d4cc2',
  '7149796d-7a38-4407-ae16-9b19be892f10',
  '6cebedb6-0b8a-41f4-834f-c6a3abbd04ae',
  '08cd9a5d-da1b-494a-93ef-34cd2944d511',
  '28c45d01-9ac8-4b7f-9ff8-fe49695e8d32',
  '1ad19239-2b23-4177-a278-e3e77abad8f6',
  'a36fa029-1683-4bad-a1c5-a5177042e191',
  '6c00d9f2-949f-4eae-8219-06ea5a0e5cfc',
  '333474c4-a3f3-4666-bd0a-2926581f3757',
  'f4bb4e7e-22e0-430c-8264-8bcbd7c94359',
  '68d62445-ba9f-4388-893e-a8836e7d61e3',
  '5aff3bc5-5e47-443a-87dd-d9d349934f45',
  '70b5b34d-5eb3-4d96-9335-9a60f577b496',
  'f8503066-6e82-4ee6-818e-ee10ff9c9cac',
  '74792021-af0e-4683-988b-88fee9bcaf68',
  '7eff3fff-9e1e-4031-9f2f-02e1160e7094',
  '282e8b8d-d5d3-4a16-a4de-e90c978a6078',
  '06bbb302-2b73-4e6a-919b-f427d2114851',
  '886857f1-e8b7-4024-984a-a1361eeb4d13',
  '44f0bc38-dce2-48e6-a877-4430a58046ae',
  '2b862100-bfc9-4ed5-b95c-ae5af770ee47',
  'd4f70e5c-19ff-42a0-98a6-11a44d2a96a3'
);

-- this_or_that_prompts: 27 rows across 20 duplicate groups
update public.this_or_that_prompts
set active = false
where id in (
  '2319a9f1-aa43-42a4-b87e-e25b48bc9c56',
  '418d148e-00f6-4651-b817-101626992959',
  '17f7b731-8d1c-487f-8f4e-65ddce82b48d',
  '5f60a7c8-845e-4d98-b7e2-b82e328682f9',
  '1cf19cd3-688d-42d9-b80e-f89ac56f6ad4',
  '04cec026-12fb-403e-9707-4794f910dcd6',
  '36981ae7-3624-47ed-be8d-4b2462389221',
  '84116f5c-a427-4cb8-80e5-8254a92dd438',
  '32321965-8e5a-4976-b401-f71b781735af',
  '44936fb1-2807-414b-987d-92aa58f41690',
  '69f80344-9dfc-4835-b416-8304d44654e6',
  'a314ec7c-d121-4745-8db7-5380900e7569',
  '72e562ca-2e14-4eec-8cb7-c8ceaef8fa84',
  '3d8e4d67-d248-41d0-a78c-e2ff66b24ae8',
  '20c44f5e-5079-4b18-80a2-f1beb80401ba',
  '80fa4051-9585-4913-b9f1-42bdd3ccd53d',
  '865b4327-5c34-411a-abcc-d975a8e54bdc',
  '0ae11a87-4ddd-47f2-92a9-09c1836ed706',
  '89c23adc-27a4-428d-94b9-8ae71d18ffe5',
  '295ed7a5-e684-4951-82da-36e86876c93f',
  'ae212c2a-1c09-40ce-9294-7976389d115b',
  '34996c8c-29f8-4ff9-8a1f-bfa2a14fcb70',
  '44b4919c-bc79-4a56-9c1f-8ce67762d092',
  '8258c3d4-575b-449f-b805-aaef358d888c',
  '2f0b7298-cf41-49bb-89e5-dc8cb3d993ef',
  '19e62fc3-6bea-4b3a-92b2-a9b83a22bea8',
  'b38a47ac-2c55-4596-b9d2-ed3a58b56c5b'
);

-- deep_conversation_topics: 30 rows across 24 duplicate groups
update public.deep_conversation_topics
set active = false
where id in (
  '990fb00f-483e-414b-be31-f7cafd8d7d47',
  '45349a10-3c00-4de5-aa37-e6be01eea57e',
  '53dbf65f-1ec1-44c2-b1b4-0601a3cadbd6',
  'cf09583c-fe29-427b-813c-b7aa14adc4bb',
  '615b986d-428c-4bba-958e-a2f94b9086f0',
  '86a976e9-bec7-4475-aead-32d702bfcebf',
  'c95cd946-3263-45f5-a4e5-dd6c4bfc2502',
  '78a522ee-aa03-4d00-a039-843c8adc7cdd',
  '0483126d-bff4-419c-ab0f-0ab53c30ddf5',
  '8e3079d4-fc7a-4d98-9a84-bc054fea708c',
  '14f30cfe-3e3d-4225-bd60-5eda3d96e026',
  '3cc669c6-8952-4639-8af7-31528162c0b7',
  'cc057939-c28d-4976-b9b4-906c2b5a8399',
  '68b7d19e-6caa-4fcf-b776-4a3d5b5148b5',
  '9c39f2fc-9c4d-48fb-8878-8f2f4319d109',
  'd632e967-8970-4650-ab53-76dda7277e4b',
  '7b410421-6e10-4a67-a213-c964cd394cea',
  'bcd910a1-5727-403e-b660-f4f9080a2f43',
  '91b4e0a2-da0c-48a7-9508-a56bea98d9cc',
  '4aae0fea-f685-483f-ac36-b2e6e6464fec',
  '8991438f-1803-401c-8610-edb8bc4e39d7',
  '480d7d3f-820a-49cb-9fdb-da53ad02232f',
  'e43364b2-8459-4853-a7f0-5482fb146c8e',
  'c75370e6-0973-4aa9-96de-aaabb16cfbe1',
  'ff3ef1cf-29ad-40e7-89ed-a262976479eb',
  '005fa8e3-18b4-4583-bdaa-202d3a3ada62',
  '63f17435-10d7-48d5-a280-3ed409bcf14c',
  '72ba00fd-a2ab-450e-939f-9ca68245ea2f',
  'e0f50c98-763a-4d96-8534-b0becc34abd5',
  '0c12bb83-049b-4794-9e0d-f5d34351c8dc'
);
