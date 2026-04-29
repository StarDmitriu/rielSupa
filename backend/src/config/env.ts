export function requireEnv(name: string): string {
  const v = String(process.env[name] || '').trim();
  if (!v) throw new Error(`Missing env: ${name}`);
  return v;
}

export function requireAnyEnv(names: string[]): string {
  for (const name of names) {
    const v = String(process.env[name] || '').trim();
    if (v) return v;
  }

  throw new Error(`Missing env: one of ${names.join(', ')}`);
}
