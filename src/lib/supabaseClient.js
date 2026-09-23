import { createClient } from '@supabase/supabase-js'

// Get values from .env
const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// Create and export client
export const supabase = createClient(supabaseUrl, supabaseAnonKey)