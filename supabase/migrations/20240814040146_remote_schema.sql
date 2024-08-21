set check_function_bodies = off;

CREATE OR REPLACE FUNCTION storage.extension(name text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
_parts text[];
_filename text;
BEGIN
    select string_to_array(name, '/') into _parts;
    select _parts[array_length(_parts,1)] into _filename;
    -- @todo return the last part instead of 2
    return split_part(_filename, '.', 2);
END
$function$
;

CREATE OR REPLACE FUNCTION storage.filename(name text)
 RETURNS text
 LANGUAGE plpgsql
AS $function$
DECLARE
_parts text[];
BEGIN
    select string_to_array(name, '/') into _parts;
    return _parts[array_length(_parts,1)];
END
$function$
;

CREATE OR REPLACE FUNCTION storage.foldername(name text)
 RETURNS text[]
 LANGUAGE plpgsql
AS $function$
DECLARE
_parts text[];
BEGIN
    select string_to_array(name, '/') into _parts;
    return _parts[1:array_length(_parts,1)-1];
END
$function$
;

grant delete on table "storage"."s3_multipart_uploads" to "postgres";

grant insert on table "storage"."s3_multipart_uploads" to "postgres";

grant references on table "storage"."s3_multipart_uploads" to "postgres";

grant select on table "storage"."s3_multipart_uploads" to "postgres";

grant trigger on table "storage"."s3_multipart_uploads" to "postgres";

grant truncate on table "storage"."s3_multipart_uploads" to "postgres";

grant update on table "storage"."s3_multipart_uploads" to "postgres";

grant delete on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant insert on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant references on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant select on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant trigger on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant truncate on table "storage"."s3_multipart_uploads_parts" to "postgres";

grant update on table "storage"."s3_multipart_uploads_parts" to "postgres";

create policy "Allow delete for authenticated users "
on "storage"."objects"
as permissive
for delete
to authenticated
using ((bucket_id = 'user_resume_bucket'::text));


create policy "Allow delete for authenticated users"
on "storage"."objects"
as permissive
for delete
to authenticated
using ((bucket_id = 'user_avatar_bucket'::text));


create policy "Allow insert for authenticated users "
on "storage"."objects"
as permissive
for insert
to authenticated
with check ((bucket_id = 'user_avatar_bucket'::text));


create policy "Allow insert for authenticated users"
on "storage"."objects"
as permissive
for insert
to authenticated
with check ((bucket_id = 'user_resume_bucket'::text));


create policy "Allow select for authenticated users "
on "storage"."objects"
as permissive
for select
to authenticated
using ((bucket_id = 'user_resume_bucket'::text));


create policy "Allow select for authenticated users"
on "storage"."objects"
as permissive
for select
to authenticated
using ((bucket_id = 'user_avatar_bucket'::text));


create policy "Allow update for authenticated users"
on "storage"."objects"
as permissive
for update
to authenticated
using ((bucket_id = 'user_avatar_bucket'::text));


create policy "Allow update for authenticated"
on "storage"."objects"
as permissive
for update
to authenticated
using ((bucket_id = 'user_resume_bucket'::text));


create policy "Give access to a file to user fk475a_0"
on "storage"."objects"
as permissive
for insert
to public
with check (true);


create policy "Give all access to authenticated user fk475a_0"
on "storage"."objects"
as permissive
for select
to authenticated
using ((bucket_id = 'team_avatar_bucket'::text));


create policy "Give all access to authenticated user fk475a_1"
on "storage"."objects"
as permissive
for insert
to authenticated
with check ((bucket_id = 'team_avatar_bucket'::text));


create policy "Give all access to authenticated user fk475a_2"
on "storage"."objects"
as permissive
for update
to authenticated
using ((bucket_id = 'team_avatar_bucket'::text));


create policy "Give all access to authenticated user fk475a_3"
on "storage"."objects"
as permissive
for delete
to authenticated
using ((bucket_id = 'team_avatar_bucket'::text));



