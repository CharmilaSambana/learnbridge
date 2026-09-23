# EduTrack Hub

bro the website should contain

a index page in which the user will be given to choose whether it is student login and teacher login after selecting they have to register when they are new to the website if they have an account already then they can login the credentials are saved in the database

after login in the student should have to select his regulation such as 25 or 24 after login in the teacher have to add their subjects with the regulations they have been teaching

now the faculty will send pdf of their respective subjects by selecting the regulation and subject as faculty deals with same subjects with different regulation students

in the faculty page it have to show that how many students have seen their pdf and how many them have downloaded it. BAsed on this a graph have to be designed.

This project was built with [Lovable](https://lovable.dev).

**Live app**: https://academiccontents.lovable.app

## Build with Lovable

Continue developing this project in the [Lovable editor](https://lovable.dev/projects/4ac96d82-5dee-42fb-978b-8d78d7abbf46).

- **Ship faster**: describe what you want to build and Lovable handles the code.
- **Stay in sync**: every change made in Lovable is committed straight to this repository.
- **Full ownership**: this code is yours. Push to `main` on GitHub and your changes sync back into Lovable, ready for your next prompt.

## Development

Prefer working locally? You need Node.js and npm — [install with nvm](https://github.com/nvm-sh/nvm#installing-and-updating).

```sh
git clone <this-repository-url>
cd <repository-name>
npm i
npm run dev
```

## Administration setup

Apply the migration in `supabase/migrations/20260922110000_admin_portal.sql` using the Supabase CLI or SQL editor. Then create a normal account for the first administrator and run this once in the Supabase SQL editor (replace the email):

```sql
insert into public.user_roles (user_id, role)
select id, 'admin'::public.app_role from auth.users where email = 'admin@example.com'
on conflict do nothing;

update public.profiles set is_approved = true, approved_at = now()
where id = (select id from auth.users where email = 'admin@example.com');
```

After this first setup, use the **Admin** portal to approve registrations, convert student/faculty roles, grant administrator access, view login and material activity, and delete PDFs. Faculty files are automatically stored under `materials/<faculty-user-id>/`.
