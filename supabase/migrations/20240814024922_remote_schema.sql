
SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

CREATE EXTENSION IF NOT EXISTS "pgsodium" WITH SCHEMA "pgsodium";

CREATE EXTENSION IF NOT EXISTS "plv8" WITH SCHEMA "pg_catalog";

CREATE EXTENSION IF NOT EXISTS "pg_graphql" WITH SCHEMA "graphql";

CREATE EXTENSION IF NOT EXISTS "pg_stat_statements" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgaudit" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgcrypto" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "pgjwt" WITH SCHEMA "extensions";

CREATE EXTENSION IF NOT EXISTS "supabase_vault" WITH SCHEMA "vault";

CREATE EXTENSION IF NOT EXISTS "uuid-ossp" WITH SCHEMA "extensions";

CREATE OR REPLACE FUNCTION "public"."handle_delete_team_user_trigger"() RETURNS "trigger"
    LANGUAGE "plv8" SECURITY DEFINER
    AS $_$try {
    plv8.elog(LOG, 'handle delete team user trigger: started.');
  
    // -- remove the deleted team user inside the group chat
    var team_chat_id = plv8.execute('SELECT id FROM public.team_chats WHERE team_id = $1 AND is_group_chat = $2 LIMIT 1', [OLD.team_id, true])[0].id;
    plv8.execute('DELETE FROM public.team_chat_users WHERE user_id = $1 AND chat_id = $2', [OLD.user_id, team_chat_id]);
    plv8.execute('INSERT INTO public.team_chat_events (chat_id, user_id, event_type) VALUES($1, $2, $3)', [team_chat_id, OLD.user_id, 'left']);

    plv8.elog(LOG, 'handle delete team user trigger: remove user from team chat done');
  
    return OLD;
  
} catch (error) {
    plv8.elog(ERROR, 'handle delete team user trigger error:' + error.message);
} finally {
    plv8.elog(LOG, 'handle delete team user trigger: finished');
}$_$;

ALTER FUNCTION "public"."handle_delete_team_user_trigger"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_new_team_trigger"() RETURNS "trigger"
    LANGUAGE "plv8" SECURITY DEFINER
    AS $_$try {
  plv8.elog(LOG, 'handle new team trigger: started.');

  var uuid = plv8.execute('SELECT uuid_generate_v4()')[0].uuid_generate_v4;

  plv8.execute('INSERT INTO public.team_chats (id, team_id, is_group_chat) VALUES ($1, $2, $3)', [uuid, NEW.id, true]);

  /*
  var owner_id = plv8.execute('SELECT user_id FROM public.team_users WHERE is_owner = $1 LIMIT 1', [true])[0].user_id;

  plv8.execute('INSERT INTO public.team_chat_users (chat_id, user_id) VALUES($1, $2)', [uuid, owner_id]);
  */
  
  plv8.elog(LOG, 'handle new team trigger: insert team chat done');

  return NEW;

} catch (error) {
  plv8.elog(ERROR, 'handle new team trigger error:' + error.message);
} finally {
  plv8.elog(LOG, 'handle new team trigger: finished');
}$_$;

ALTER FUNCTION "public"."handle_new_team_trigger"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_new_team_user_trigger"() RETURNS "trigger"
    LANGUAGE "plv8" SECURITY DEFINER
    AS $_$try {
    plv8.elog(LOG, 'handle new team user trigger: started.');
  
    // -- add the new team user inside the group chat
    var team_chat_id = plv8.execute('SELECT id FROM public.team_chats WHERE team_id = $1 AND is_group_chat = $2 LIMIT 1', [NEW.team_id, true])[0].id;
    plv8.execute('INSERT INTO public.team_chat_users (chat_id, user_id) VALUES($1, $2)', [team_chat_id, NEW.user_id]);
    plv8.execute('INSERT INTO public.team_chat_events (chat_id, user_id, event_type) VALUES($1, $2, $3)', [team_chat_id, NEW.user_id, 'joined']);
  
    // -- Get the rest of team members aside from the newly joined one
    var members = plv8.execute('SELECT user_id FROM public.team_users WHERE user_id != $1 AND team_id = $2', [NEW.user_id, NEW.team_id]);
  
    for (var i = 0; i < members.length; i++) {
      var member = members[i];
      
      // -- Check if the chat room exists between the two members
      var chat_room = plv8.execute('SELECT public.team_chats.id, COUNT(public.team_chat_users.user_id)  FROM public.team_chats INNER JOIN public.team_chat_users ON public.team_chats.id = public.team_chat_users.chat_id WHERE public.team_chat_users.user_id IN ($1, $2) AND public.team_chats.is_group_chat = $3 AND public.team_chats.team_id = $4 GROUP BY public.team_chats.id HAVING COUNT(public.team_chat_users.user_id) >=2', [NEW.user_id, member.user_id, false, NEW.team_id]);
      
      plv8.elog(LOG, 'chat_room: ' + chat_room);

      if (chat_room.length > 0) {
        continue;
      }
  
      var uuid = plv8.execute('SELECT uuid_generate_v4()')[0].uuid_generate_v4;
  
      // -- create new chat room
      plv8.execute('INSERT INTO public.team_chats (id, team_id, is_group_chat) VALUES ($1, $2, $3)', [uuid, NEW.team_id, false]);
  
      // -- Add both users into the chat room
      plv8.execute('INSERT INTO public.team_chat_users (chat_id, user_id) VALUES($1, $2)', [uuid, member.user_id]);
      plv8.execute('INSERT INTO public.team_chat_users (chat_id, user_id) VALUES($1, $2)', [uuid, NEW.user_id]);
    }
    
    plv8.elog(LOG, 'handle new team user trigger: insert user chats done');
  
    return NEW;
  
} catch (error) {
    plv8.elog(ERROR, 'handle new team user trigger error:' + error.message);
} finally {
    plv8.elog(LOG, 'handle new team user trigger: finished');
}$_$;

ALTER FUNCTION "public"."handle_new_team_user_trigger"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_new_user_trigger"() RETURNS "trigger"
    LANGUAGE "plpgsql" SECURITY DEFINER
    AS $$begin
  insert into public.users (id)
  values (new.id);
  insert into public.preferences (user_id) values (new.id);
  return new;
end;$$;

ALTER FUNCTION "public"."handle_new_user_trigger"() OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_onboard_user"("request_data" "json") RETURNS "void"
    LANGUAGE "plv8"
    AS $_$try {
  plv8.elog(LOG, 'handle onboard user started w/ request_data: ' + JSON.stringify(request_data));
  // --Extract JSON params
  var requestObj = request_data;
  var user = requestObj.user; 
  var selected_skills = user.preference.skills_interests;
  var selected_categories = user.preference.categories;
  var experiences = user.experiences;
  var accomplishments = user.accomplishments;

  var auth_user_id = user.id;

  plv8.elog(LOG, 'handle onboard user id: ' + auth_user_id);

  // --Update user data onboarding
  plv8.execute('UPDATE public.users SET first_name = $1, last_name = $2, title = $3, degree_programme_id = $4, about = $5, is_onboarded = true, updated_at = now() WHERE id = $6', user.first_name, user.last_name, user.title, user.degree_programme_id, user.about, auth_user_id);
  plv8.elog(LOG, 'handle onboard user: Update user info successful');

  // -- Select preference of specific user
  var result = plv8.execute('SELECT * FROM public.preferences WHERE user_id = $1', auth_user_id);

  plv8.elog(LOG, 'handle onboard user preference result: ' + JSON.stringify(result));

  var preference_id = result[0].id;

  // --Update skills
  for (var i = 0; i < selected_skills.length; i++) {
    var skill = selected_skills[i];

    plv8.execute('INSERT INTO public.selected_skills (emsi_id, name) VALUES ($1, $2) ON CONFLICT (emsi_id) DO NOTHING', skill.emsi_id, skill.name);

    var result = plv8.execute('SELECT id FROM public.selected_skills WHERE emsi_id = $1 LIMIT 1', skill.emsi_id);

    if (result.length == 0) {
      continue;
    }

    var skill_id = result[0].id;

    plv8.execute('INSERT INTO public.skills_preferences ' +
  '(selected_skill_id, preference_id) VALUES ($1, $2)', skill_id, preference_id);
  }
  plv8.elog(LOG, 'Handle onboard usr: Insert skills successful');

  // --Insert user selected categories
  for (var i = 0; i < selected_categories.length; i++) {
    var category = selected_categories[i];

    plv8.execute('INSERT INTO public.categories_preferences (category_id, preference_id) VALUES ($1, $2)', category.id, preference_id);
  }
  plv8.elog(LOG, 'Handle onboard user: Insert selected categories successful');

  // --Insert experiences of user
  for (var i = 0; i < experiences.length; i++) {
    var experience = experiences[i];

    plv8.execute('INSERT INTO public.experiences (title, company_name, is_current, start_date, end_date, description, user_id) VALUES ($1, $2, $3, $4, $5, $6, $7)', experience.title, experience.company_name, experience.is_current, experience.start_date, experience.end_date, experience.description, auth_user_id);
  }
  plv8.elog(LOG, 'Handle onboard user: Insert user experiences success');

  // --Insert accomplishments of user
  for (var i = 0; i < accomplishments.length; i++) {
    var accomplishment = accomplishments[i];

    plv8.execute('INSERT INTO public.accomplishments (title, issuer, is_active, start_date, end_date, description, user_id) VALUES ($1, $2, $3, $4, $5, $6, $7)', accomplishment.title, accomplishment.issuer, accomplishment.is_active, accomplishment.start_date, accomplishment.end_date, accomplishment.description, auth_user_id);
  }
  plv8.elog(LOG, 'Handle onboard user: Insert user accomplishments success');

  return;

} catch (error) {

  plv8.elog(ERROR, 'handle onboard user error:' + error.message);

} finally {
  plv8.elog(LOG, 'handle onboard user finished');
}$_$;

ALTER FUNCTION "public"."handle_onboard_user"("request_data" "json") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_user_preference_update"("request_data" "json") RETURNS "void"
    LANGUAGE "plv8"
    AS $_$try {
  plv8.elog(LOG, 'handle user preference update started w/ request_data: ' + JSON.stringify(request_data));
  // --Extract JSON params
  var requestObj = request_data;
  var preference = requestObj.preference; 
  var selected_categories = preference.categories;

  // --Delete skills_preferences records first
  plv8.execute('DELETE FROM public.categories_preferences WHERE preference_id = $1', [preference.id]);

  // --Update skills
  for (var i = 0; i < selected_categories.length; i++) {
    var category = selected_categories[i];

    plv8.execute('INSERT INTO public.categories_preferences ' +
    '(category_id, preference_id) VALUES ($1, $2)', category.id, preference.id);
  }
  plv8.elog(LOG, 'handle user preference update: Update skills successful');

  return;

} catch (error) {

  plv8.elog(ERROR, 'handle user preference update error:' + error.message);

} finally {
  plv8.elog(LOG, 'handle user preference update finished');
}$_$;

ALTER FUNCTION "public"."handle_user_preference_update"("request_data" "json") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."handle_user_selected_skills_update"("request_data" "json") RETURNS "void"
    LANGUAGE "plv8"
    AS $_$try {
  plv8.elog(LOG, 'handle user selected_skill update started w/ request_data: ' + JSON.stringify(request_data));
  // --Extract JSON params
  var requestObj = request_data;
  var preference = requestObj.preference; 
  var selected_skills = preference.skills_interests;

  // --Delete skills_preferences records first
  plv8.execute('DELETE FROM public.skills_preferences WHERE preference_id = $1', [preference.id]);

  // --Update skills
  for (var i = 0; i < selected_skills.length; i++) {
    var skill = selected_skills[i];

    plv8.execute('INSERT INTO public.selected_skills (emsi_id, name) VALUES ($1, $2) ON CONFLICT (emsi_id) DO NOTHING', skill.emsi_id, skill.name);

    var result = plv8.execute('SELECT id FROM public.selected_skills WHERE emsi_id = $1 LIMIT 1', skill.emsi_id);

    if (result.length == 0) {
      continue;
    }

    var skill_id = result[0].id;

    plv8.execute('INSERT INTO public.skills_preferences ' +
  '(selected_skill_id, preference_id) VALUES ($1, $2)', skill_id, preference.id);
  }
  plv8.elog(LOG, 'handle user selected_skill update: Update skills successful');

  return;

} catch (error) {

  plv8.elog(ERROR, 'handle user selected_skill update error:' + error.message);

} finally {
  plv8.elog(LOG, 'handle user selected_skill update finished');
}$_$;

ALTER FUNCTION "public"."handle_user_selected_skills_update"("request_data" "json") OWNER TO "postgres";

CREATE OR REPLACE FUNCTION "public"."plv8_test_function"() RETURNS "void"
    LANGUAGE "plv8"
    AS $$plv8.elog(LOG, 'test');$$;

ALTER FUNCTION "public"."plv8_test_function"() OWNER TO "postgres";

SET default_tablespace = '';

SET default_table_access_method = "heap";

CREATE TABLE IF NOT EXISTS "public"."accomplishments" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "title" character varying,
    "issuer" character varying,
    "description" "text",
    "start_date" "date",
    "end_date" "date",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "is_active" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."accomplishments" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."categories" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "name" character varying NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."categories" OWNER TO "postgres";

COMMENT ON TABLE "public"."categories" IS 'Stores all the team categories in the application';

CREATE TABLE IF NOT EXISTS "public"."categories_preferences" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "category_id" "uuid" NOT NULL,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "preference_id" "uuid" NOT NULL
);

ALTER TABLE "public"."categories_preferences" OWNER TO "postgres";

COMMENT ON TABLE "public"."categories_preferences" IS 'A relational table between categories and preferences to map M:M relationships';

CREATE TABLE IF NOT EXISTS "public"."degree_programmes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "name" character varying NOT NULL,
    "type" character varying DEFAULT 'undergraduate'::character varying NOT NULL
);

ALTER TABLE "public"."degree_programmes" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."experiences" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "title" character varying,
    "company_name" character varying,
    "is_current" boolean NOT NULL,
    "start_date" "date",
    "end_date" "date",
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "description" "text"
);

ALTER TABLE "public"."experiences" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."milestones" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "title" character varying NOT NULL,
    "is_completed" boolean DEFAULT false NOT NULL,
    "end_date" "date",
    "description" character varying,
    "team_id" "uuid" NOT NULL,
    "start_date" "date"
);

ALTER TABLE "public"."milestones" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."preferences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL
);

ALTER TABLE "public"."preferences" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."request_chat_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "update_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "message_content" "text" NOT NULL
);

ALTER TABLE "public"."request_chat_messages" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."request_chat_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "chat_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL
);

ALTER TABLE "public"."request_chat_users" OWNER TO "postgres";

COMMENT ON TABLE "public"."request_chat_users" IS 'The request chat participants';

CREATE TABLE IF NOT EXISTS "public"."request_chats" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "applicant_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."request_chats" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."request_message_seens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "message_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL
);

ALTER TABLE "public"."request_message_seens" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."roles_open" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "title" character varying NOT NULL,
    "description" character varying,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "team_id" "uuid" NOT NULL
);

ALTER TABLE "public"."roles_open" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."selected_skills" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "name" character varying,
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "emsi_id" "text" NOT NULL
);

ALTER TABLE "public"."selected_skills" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."skills_preferences" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "selected_skill_id" "uuid" NOT NULL,
    "preference_id" "uuid"
);

ALTER TABLE "public"."skills_preferences" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."team_applicants" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "team_id" "uuid" NOT NULL,
    "applied_at" timestamp with time zone,
    "status" character varying DEFAULT 'pending'::character varying NOT NULL
);

ALTER TABLE "public"."team_applicants" OWNER TO "postgres";

COMMENT ON TABLE "public"."team_applicants" IS 'Table to store applicants in a team';

CREATE TABLE IF NOT EXISTS "public"."team_chat_events" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "chat_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "event_type" character varying NOT NULL
);

ALTER TABLE "public"."team_chat_events" OWNER TO "postgres";

COMMENT ON TABLE "public"."team_chat_events" IS 'Events occured within each team chats';

CREATE TABLE IF NOT EXISTS "public"."team_chat_messages" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "message_content" "text" NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL
);

ALTER TABLE "public"."team_chat_messages" OWNER TO "postgres";

COMMENT ON TABLE "public"."team_chat_messages" IS 'Table to contain all message related records within team chats';

CREATE TABLE IF NOT EXISTS "public"."team_chat_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "chat_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."team_chat_users" OWNER TO "postgres";

COMMENT ON TABLE "public"."team_chat_users" IS 'Team chat participants';

CREATE TABLE IF NOT EXISTS "public"."team_chats" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "team_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "is_group_chat" boolean NOT NULL
);

ALTER TABLE "public"."team_chats" OWNER TO "postgres";

COMMENT ON TABLE "public"."team_chats" IS 'Chats found in each team including team and individual chats';

CREATE TABLE IF NOT EXISTS "public"."team_message_seens" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "message_id" "uuid" NOT NULL,
    "user_id" "uuid" NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"()
);

ALTER TABLE "public"."team_message_seens" OWNER TO "postgres";

COMMENT ON TABLE "public"."team_message_seens" IS 'Contains seen records of team messages';

CREATE TABLE IF NOT EXISTS "public"."team_users" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "team_id" "uuid" NOT NULL,
    "position" character varying NOT NULL,
    "is_owner" boolean DEFAULT false NOT NULL
);

ALTER TABLE "public"."team_users" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."teams" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "updated_at" timestamp with time zone DEFAULT "now"() NOT NULL,
    "team_name" character varying NOT NULL,
    "current_members" bigint DEFAULT '1'::bigint NOT NULL,
    "max_members" bigint NOT NULL,
    "commitment" character varying NOT NULL,
    "is_listed" boolean DEFAULT true NOT NULL,
    "is_current" boolean DEFAULT true NOT NULL,
    "start_date" "date" NOT NULL,
    "end_date" "date",
    "project_category" character varying NOT NULL,
    "description" character varying NOT NULL,
    "interest" "json"[] NOT NULL,
    "avatar" character varying,
    "interest_name" character varying[]
);

ALTER TABLE "public"."teams" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."test" (
    "created_at" timestamp with time zone DEFAULT "now"(),
    "name" "text" DEFAULT ''::"text",
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL
);

ALTER TABLE "public"."test" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_avatars" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "file_name" character varying NOT NULL,
    "file_identifier" character varying NOT NULL
);

ALTER TABLE "public"."user_avatars" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."user_resumes" (
    "id" "uuid" DEFAULT "gen_random_uuid"() NOT NULL,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "user_id" "uuid" NOT NULL,
    "file_name" character varying NOT NULL,
    "file_identifier" character varying
);

ALTER TABLE "public"."user_resumes" OWNER TO "postgres";

CREATE TABLE IF NOT EXISTS "public"."users" (
    "id" "uuid" NOT NULL,
    "avatar" character varying,
    "first_name" character varying,
    "last_name" character varying,
    "title" character varying,
    "created_at" timestamp with time zone DEFAULT "now"(),
    "updated_at" timestamp with time zone DEFAULT "now"(),
    "resume" character varying,
    "degree_programme_id" "uuid",
    "is_onboarded" boolean DEFAULT false NOT NULL,
    "about" "text",
    "username" "text"
);

ALTER TABLE "public"."users" OWNER TO "postgres";

COMMENT ON TABLE "public"."users" IS 'Table containing users of the application';

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "Users_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."accomplishments"
    ADD CONSTRAINT "accomplishment_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_name_key" UNIQUE ("name");

ALTER TABLE ONLY "public"."categories"
    ADD CONSTRAINT "categories_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."categories_preferences"
    ADD CONSTRAINT "categories_preferences_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."degree_programmes"
    ADD CONSTRAINT "majors_name_key" UNIQUE ("name");

ALTER TABLE ONLY "public"."degree_programmes"
    ADD CONSTRAINT "majors_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."milestones"
    ADD CONSTRAINT "milestones_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."preferences"
    ADD CONSTRAINT "preferences_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."preferences"
    ADD CONSTRAINT "preferences_user_id_key" UNIQUE ("user_id");

ALTER TABLE ONLY "public"."request_chat_messages"
    ADD CONSTRAINT "request_chat_messages_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."request_chat_users"
    ADD CONSTRAINT "request_chat_users_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."request_chats"
    ADD CONSTRAINT "request_chats_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."request_message_seens"
    ADD CONSTRAINT "request_message_seens_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_resumes"
    ADD CONSTRAINT "resumes_file_identifier_key" UNIQUE ("file_identifier");

ALTER TABLE ONLY "public"."user_resumes"
    ADD CONSTRAINT "resumes_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_resumes"
    ADD CONSTRAINT "resumes_user_id_key" UNIQUE ("user_id");

ALTER TABLE ONLY "public"."roles_open"
    ADD CONSTRAINT "roles_open_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."selected_skills"
    ADD CONSTRAINT "selected_skills_emsi_id_key" UNIQUE ("emsi_id");

ALTER TABLE ONLY "public"."selected_skills"
    ADD CONSTRAINT "skills_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."skills_preferences"
    ADD CONSTRAINT "skills_user_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."team_applicants"
    ADD CONSTRAINT "team_applicants_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."team_chat_events"
    ADD CONSTRAINT "team_chat_events_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."team_chat_messages"
    ADD CONSTRAINT "team_chat_messages_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."team_chat_users"
    ADD CONSTRAINT "team_chat_users_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."team_chats"
    ADD CONSTRAINT "team_chats_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."team_message_seens"
    ADD CONSTRAINT "team_message_seens_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."team_users"
    ADD CONSTRAINT "team_users_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."teams"
    ADD CONSTRAINT "teams_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."test"
    ADD CONSTRAINT "test_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_avatars"
    ADD CONSTRAINT "user_avatars_file_identifier_key" UNIQUE ("file_identifier");

ALTER TABLE ONLY "public"."user_avatars"
    ADD CONSTRAINT "user_avatars_pkey" PRIMARY KEY ("id");

ALTER TABLE ONLY "public"."user_avatars"
    ADD CONSTRAINT "user_avatars_user_id_key" UNIQUE ("user_id");

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_key" UNIQUE ("id");

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_username_key" UNIQUE ("username");

ALTER TABLE ONLY "public"."experiences"
    ADD CONSTRAINT "work_experiences_pkey" PRIMARY KEY ("id");

CREATE OR REPLACE TRIGGER "on_team_created" AFTER INSERT ON "public"."teams" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_team_trigger"();

CREATE OR REPLACE TRIGGER "on_team_user_created" AFTER INSERT ON "public"."team_users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_new_team_user_trigger"();

CREATE OR REPLACE TRIGGER "on_team_user_deleted" AFTER DELETE ON "public"."team_users" FOR EACH ROW EXECUTE FUNCTION "public"."handle_delete_team_user_trigger"();

ALTER TABLE ONLY "public"."accomplishments"
    ADD CONSTRAINT "accomplishments_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");

ALTER TABLE ONLY "public"."categories_preferences"
    ADD CONSTRAINT "categories_preferences_category_id_fkey" FOREIGN KEY ("category_id") REFERENCES "public"."categories"("id");

ALTER TABLE ONLY "public"."categories_preferences"
    ADD CONSTRAINT "categories_preferences_preference_id_fkey" FOREIGN KEY ("preference_id") REFERENCES "public"."preferences"("id");

ALTER TABLE ONLY "public"."experiences"
    ADD CONSTRAINT "experiences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");

ALTER TABLE ONLY "public"."milestones"
    ADD CONSTRAINT "milestones_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id");

ALTER TABLE ONLY "public"."preferences"
    ADD CONSTRAINT "preferences_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");

ALTER TABLE ONLY "public"."request_chat_messages"
    ADD CONSTRAINT "request_chat_messages_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_chat_messages"
    ADD CONSTRAINT "request_chat_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_chat_users"
    ADD CONSTRAINT "request_chat_users_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."request_chats"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_chat_users"
    ADD CONSTRAINT "request_chat_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_chats"
    ADD CONSTRAINT "request_chats_applicant_id_fkey" FOREIGN KEY ("applicant_id") REFERENCES "public"."team_applicants"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_message_seens"
    ADD CONSTRAINT "request_message_seens_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."request_chat_messages"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."request_message_seens"
    ADD CONSTRAINT "request_message_seens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."roles_open"
    ADD CONSTRAINT "roles_open_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id");

ALTER TABLE ONLY "public"."skills_preferences"
    ADD CONSTRAINT "skills_preferences_preference_id_fkey" FOREIGN KEY ("preference_id") REFERENCES "public"."preferences"("id");

ALTER TABLE ONLY "public"."skills_preferences"
    ADD CONSTRAINT "skills_preferences_selected_skill_id_fkey" FOREIGN KEY ("selected_skill_id") REFERENCES "public"."selected_skills"("id");

ALTER TABLE ONLY "public"."team_applicants"
    ADD CONSTRAINT "team_applicants_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id");

ALTER TABLE ONLY "public"."team_applicants"
    ADD CONSTRAINT "team_applicants_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");

ALTER TABLE ONLY "public"."team_chat_events"
    ADD CONSTRAINT "team_chat_events_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."team_chats"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_chat_events"
    ADD CONSTRAINT "team_chat_events_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_chat_messages"
    ADD CONSTRAINT "team_chat_messages_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."team_chats"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_chat_messages"
    ADD CONSTRAINT "team_chat_messages_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_chat_users"
    ADD CONSTRAINT "team_chat_users_chat_id_fkey" FOREIGN KEY ("chat_id") REFERENCES "public"."team_chats"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_chat_users"
    ADD CONSTRAINT "team_chat_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_chats"
    ADD CONSTRAINT "team_chats_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_message_seens"
    ADD CONSTRAINT "team_message_seens_message_id_fkey" FOREIGN KEY ("message_id") REFERENCES "public"."team_chat_messages"("id");

ALTER TABLE ONLY "public"."team_message_seens"
    ADD CONSTRAINT "team_message_seens_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id");

ALTER TABLE ONLY "public"."team_users"
    ADD CONSTRAINT "team_users_team_id_fkey" FOREIGN KEY ("team_id") REFERENCES "public"."teams"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."team_users"
    ADD CONSTRAINT "team_users_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_avatars"
    ADD CONSTRAINT "user_avatars_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."user_resumes"
    ADD CONSTRAINT "user_resumes_user_id_fkey" FOREIGN KEY ("user_id") REFERENCES "public"."users"("id") ON DELETE CASCADE;

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_degree_programme_id_fkey" FOREIGN KEY ("degree_programme_id") REFERENCES "public"."degree_programmes"("id");

ALTER TABLE ONLY "public"."users"
    ADD CONSTRAINT "users_id_fkey" FOREIGN KEY ("id") REFERENCES "auth"."users"("id") ON DELETE CASCADE;

CREATE POLICY "All user can see the applicants" ON "public"."team_applicants" FOR SELECT USING (true);

CREATE POLICY "All users are able to apply to any teams" ON "public"."team_applicants" FOR INSERT WITH CHECK (true);

CREATE POLICY "All users are able to create (insert) new teams" ON "public"."teams" FOR INSERT WITH CHECK (true);

CREATE POLICY "All users are able to create/join new teams" ON "public"."team_users" FOR INSERT WITH CHECK (true);

CREATE POLICY "All users are able to see the team data" ON "public"."teams" FOR SELECT USING (true);

CREATE POLICY "Enable all access for authenticated users" ON "public"."user_avatars" TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable all access for authenticated users" ON "public"."user_resumes" TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable all for authenticated users only" ON "public"."team_chat_messages" TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable all for authenticated users only" ON "public"."team_chat_users" TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable all for authenticated users only" ON "public"."team_chats" TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable delete for authenticated users" ON "public"."skills_preferences" FOR DELETE TO "authenticated" USING (true);

CREATE POLICY "Enable delete for authenticated users only" ON "public"."accomplishments" FOR DELETE TO "authenticated" USING (true);

CREATE POLICY "Enable delete for authenticated users only" ON "public"."categories_preferences" FOR DELETE TO "authenticated" USING (true);

CREATE POLICY "Enable delete for authenticated users only" ON "public"."experiences" FOR DELETE TO "authenticated" USING (true);

CREATE POLICY "Enable delete for users based on user_id" ON "public"."milestones" USING ((EXISTS ( SELECT "team_users"."id",
    "team_users"."user_id",
    "team_users"."team_id"
   FROM "public"."team_users"
  WHERE (("team_users"."team_id" = "milestones"."team_id") AND ("team_users"."user_id" = "auth"."uid"())))));

CREATE POLICY "Enable insert for authenticated users only" ON "public"."accomplishments" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."categories_preferences" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."experiences" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."selected_skills" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable insert for authenticated users only" ON "public"."skills_preferences" FOR INSERT TO "authenticated" WITH CHECK (true);

CREATE POLICY "Enable read access for all users" ON "public"."test" USING (true);

CREATE POLICY "Enable read access for authenticated users" ON "public"."accomplishments" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "Enable read access for authenticated users" ON "public"."categories" FOR SELECT USING (("auth"."uid"() IS NOT NULL));

CREATE POLICY "Enable read access for authenticated users" ON "public"."categories_preferences" FOR SELECT TO "authenticated" USING (true);

CREATE POLICY "Enable read access for authenticated users" ON "public"."degree_programmes" FOR SELECT USING (("auth"."uid"() IS NOT NULL));

CREATE POLICY "Enable read access for authenticated users" ON "public"."experiences" FOR SELECT USING (true);

CREATE POLICY "Enable read access for authenticated users" ON "public"."preferences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));

CREATE POLICY "Enable read access for authenticated users" ON "public"."selected_skills" FOR SELECT USING (("auth"."uid"() IS NOT NULL));

CREATE POLICY "Enable read access for authenticated users" ON "public"."skills_preferences" FOR SELECT USING (("auth"."uid"() IS NOT NULL));

CREATE POLICY "Enable select access for users" ON "public"."team_users" USING (true);

CREATE POLICY "Enable update for authenticated users only" ON "public"."accomplishments" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Enable update for authenticated users only" ON "public"."experiences" FOR UPDATE TO "authenticated" USING (true) WITH CHECK (true);

CREATE POLICY "Public profiles are viewable by everyone" ON "public"."users" FOR SELECT USING (true);

CREATE POLICY "Team members can leave, join teams" ON "public"."teams" FOR UPDATE USING ((EXISTS ( SELECT "team_users"."id",
    "team_users"."user_id",
    "team_users"."team_id"
   FROM "public"."team_users"
  WHERE (("team_users"."team_id" = "teams"."id") AND ("team_users"."user_id" = "auth"."uid"())))));

CREATE POLICY "Team owners are able to update accept/reject (update)" ON "public"."team_applicants" FOR UPDATE USING ((EXISTS ( SELECT "team_users"."id",
    "team_users"."user_id",
    "team_users"."team_id",
    "team_users"."is_owner"
   FROM "public"."team_users"
  WHERE (("team_users"."team_id" = "team_applicants"."team_id") AND ("team_users"."is_owner" = true) AND ("team_users"."user_id" = "auth"."uid"())))));

CREATE POLICY "Test (All Access to everyone)" ON "public"."roles_open" USING (true);

CREATE POLICY "User can update their own profile" ON "public"."users" FOR UPDATE USING (("auth"."uid"() = "id")) WITH CHECK (("auth"."uid"() = "id"));

CREATE POLICY "Users are able to delete their own application" ON "public"."team_applicants" FOR DELETE USING (("auth"."uid"() = "user_id"));

CREATE POLICY "Users are able to reapply to the team (update)" ON "public"."team_applicants" FOR UPDATE USING (("auth"."uid"() = "user_id"));

CREATE POLICY "Users are only able to see (select) their own teams" ON "public"."teams" FOR SELECT USING ((EXISTS ( SELECT "team_users"."id",
    "team_users"."user_id",
    "team_users"."team_id"
   FROM "public"."team_users"
  WHERE (("team_users"."team_id" = "teams"."id") AND ("team_users"."user_id" = "auth"."uid"())))));

CREATE POLICY "Users can insert their own profile" ON "public"."users" FOR INSERT WITH CHECK (("auth"."uid"() = "id"));

ALTER TABLE "public"."accomplishments" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."categories" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."categories_preferences" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."degree_programmes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."experiences" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."milestones" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."preferences" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."request_chat_messages" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."request_chat_users" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."request_chats" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."request_message_seens" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."roles_open" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."selected_skills" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."skills_preferences" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."team_applicants" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."team_chat_events" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."team_chat_messages" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."team_chat_users" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."team_chats" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."team_message_seens" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."team_users" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."teams" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."test" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_avatars" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."user_resumes" ENABLE ROW LEVEL SECURITY;

ALTER TABLE "public"."users" ENABLE ROW LEVEL SECURITY;

ALTER PUBLICATION "supabase_realtime" OWNER TO "postgres";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."milestones";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."request_chat_messages";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."request_chat_users";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."request_chats";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."request_message_seens";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."roles_open";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."team_applicants";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."team_chat_messages";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."team_chat_users";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."team_chats";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."team_users";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."teams";

ALTER PUBLICATION "supabase_realtime" ADD TABLE ONLY "public"."users";

REVOKE USAGE ON SCHEMA "public" FROM PUBLIC;
GRANT USAGE ON SCHEMA "public" TO "postgres";
GRANT USAGE ON SCHEMA "public" TO "anon";
GRANT USAGE ON SCHEMA "public" TO "authenticated";
GRANT USAGE ON SCHEMA "public" TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_delete_team_user_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_delete_team_user_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_delete_team_user_trigger"() TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_new_team_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_team_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_team_trigger"() TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_new_team_user_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_team_user_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_team_user_trigger"() TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_new_user_trigger"() TO "anon";
GRANT ALL ON FUNCTION "public"."handle_new_user_trigger"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_new_user_trigger"() TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_onboard_user"("request_data" "json") TO "anon";
GRANT ALL ON FUNCTION "public"."handle_onboard_user"("request_data" "json") TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_onboard_user"("request_data" "json") TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_user_preference_update"("request_data" "json") TO "anon";
GRANT ALL ON FUNCTION "public"."handle_user_preference_update"("request_data" "json") TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_user_preference_update"("request_data" "json") TO "service_role";

GRANT ALL ON FUNCTION "public"."handle_user_selected_skills_update"("request_data" "json") TO "anon";
GRANT ALL ON FUNCTION "public"."handle_user_selected_skills_update"("request_data" "json") TO "authenticated";
GRANT ALL ON FUNCTION "public"."handle_user_selected_skills_update"("request_data" "json") TO "service_role";

GRANT ALL ON FUNCTION "public"."plv8_test_function"() TO "anon";
GRANT ALL ON FUNCTION "public"."plv8_test_function"() TO "authenticated";
GRANT ALL ON FUNCTION "public"."plv8_test_function"() TO "service_role";

GRANT ALL ON TABLE "public"."accomplishments" TO "anon";
GRANT ALL ON TABLE "public"."accomplishments" TO "authenticated";
GRANT ALL ON TABLE "public"."accomplishments" TO "service_role";

GRANT ALL ON TABLE "public"."categories" TO "anon";
GRANT ALL ON TABLE "public"."categories" TO "authenticated";
GRANT ALL ON TABLE "public"."categories" TO "service_role";

GRANT ALL ON TABLE "public"."categories_preferences" TO "anon";
GRANT ALL ON TABLE "public"."categories_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."categories_preferences" TO "service_role";

GRANT ALL ON TABLE "public"."degree_programmes" TO "anon";
GRANT ALL ON TABLE "public"."degree_programmes" TO "authenticated";
GRANT ALL ON TABLE "public"."degree_programmes" TO "service_role";

GRANT ALL ON TABLE "public"."experiences" TO "anon";
GRANT ALL ON TABLE "public"."experiences" TO "authenticated";
GRANT ALL ON TABLE "public"."experiences" TO "service_role";

GRANT ALL ON TABLE "public"."milestones" TO "anon";
GRANT ALL ON TABLE "public"."milestones" TO "authenticated";
GRANT ALL ON TABLE "public"."milestones" TO "service_role";

GRANT ALL ON TABLE "public"."preferences" TO "anon";
GRANT ALL ON TABLE "public"."preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."preferences" TO "service_role";

GRANT ALL ON TABLE "public"."request_chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."request_chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."request_chat_messages" TO "service_role";

GRANT ALL ON TABLE "public"."request_chat_users" TO "anon";
GRANT ALL ON TABLE "public"."request_chat_users" TO "authenticated";
GRANT ALL ON TABLE "public"."request_chat_users" TO "service_role";

GRANT ALL ON TABLE "public"."request_chats" TO "anon";
GRANT ALL ON TABLE "public"."request_chats" TO "authenticated";
GRANT ALL ON TABLE "public"."request_chats" TO "service_role";

GRANT ALL ON TABLE "public"."request_message_seens" TO "anon";
GRANT ALL ON TABLE "public"."request_message_seens" TO "authenticated";
GRANT ALL ON TABLE "public"."request_message_seens" TO "service_role";

GRANT ALL ON TABLE "public"."roles_open" TO "anon";
GRANT ALL ON TABLE "public"."roles_open" TO "authenticated";
GRANT ALL ON TABLE "public"."roles_open" TO "service_role";

GRANT ALL ON TABLE "public"."selected_skills" TO "anon";
GRANT ALL ON TABLE "public"."selected_skills" TO "authenticated";
GRANT ALL ON TABLE "public"."selected_skills" TO "service_role";

GRANT ALL ON TABLE "public"."skills_preferences" TO "anon";
GRANT ALL ON TABLE "public"."skills_preferences" TO "authenticated";
GRANT ALL ON TABLE "public"."skills_preferences" TO "service_role";

GRANT ALL ON TABLE "public"."team_applicants" TO "anon";
GRANT ALL ON TABLE "public"."team_applicants" TO "authenticated";
GRANT ALL ON TABLE "public"."team_applicants" TO "service_role";

GRANT ALL ON TABLE "public"."team_chat_events" TO "anon";
GRANT ALL ON TABLE "public"."team_chat_events" TO "authenticated";
GRANT ALL ON TABLE "public"."team_chat_events" TO "service_role";

GRANT ALL ON TABLE "public"."team_chat_messages" TO "anon";
GRANT ALL ON TABLE "public"."team_chat_messages" TO "authenticated";
GRANT ALL ON TABLE "public"."team_chat_messages" TO "service_role";

GRANT ALL ON TABLE "public"."team_chat_users" TO "anon";
GRANT ALL ON TABLE "public"."team_chat_users" TO "authenticated";
GRANT ALL ON TABLE "public"."team_chat_users" TO "service_role";

GRANT ALL ON TABLE "public"."team_chats" TO "anon";
GRANT ALL ON TABLE "public"."team_chats" TO "authenticated";
GRANT ALL ON TABLE "public"."team_chats" TO "service_role";

GRANT ALL ON TABLE "public"."team_message_seens" TO "anon";
GRANT ALL ON TABLE "public"."team_message_seens" TO "authenticated";
GRANT ALL ON TABLE "public"."team_message_seens" TO "service_role";

GRANT ALL ON TABLE "public"."team_users" TO "anon";
GRANT ALL ON TABLE "public"."team_users" TO "authenticated";
GRANT ALL ON TABLE "public"."team_users" TO "service_role";

GRANT ALL ON TABLE "public"."teams" TO "anon";
GRANT ALL ON TABLE "public"."teams" TO "authenticated";
GRANT ALL ON TABLE "public"."teams" TO "service_role";

GRANT ALL ON TABLE "public"."test" TO "anon";
GRANT ALL ON TABLE "public"."test" TO "authenticated";
GRANT ALL ON TABLE "public"."test" TO "service_role";

GRANT ALL ON TABLE "public"."user_avatars" TO "anon";
GRANT ALL ON TABLE "public"."user_avatars" TO "authenticated";
GRANT ALL ON TABLE "public"."user_avatars" TO "service_role";

GRANT ALL ON TABLE "public"."user_resumes" TO "anon";
GRANT ALL ON TABLE "public"."user_resumes" TO "authenticated";
GRANT ALL ON TABLE "public"."user_resumes" TO "service_role";

GRANT ALL ON TABLE "public"."users" TO "anon";
GRANT ALL ON TABLE "public"."users" TO "authenticated";
GRANT ALL ON TABLE "public"."users" TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON SEQUENCES  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON FUNCTIONS  TO "service_role";

ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "postgres";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "anon";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "authenticated";
ALTER DEFAULT PRIVILEGES FOR ROLE "postgres" IN SCHEMA "public" GRANT ALL ON TABLES  TO "service_role";

RESET ALL;
