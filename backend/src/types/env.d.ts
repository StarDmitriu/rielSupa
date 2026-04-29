declare namespace NodeJS {
  interface ProcessEnv {
    JWT_SECRET: string;
    SUPABASE_URL: string;
    SUPABASE_KEY: string;
    SUPABASE_SERVICE_ROLE_KEY: string;
  }
}
