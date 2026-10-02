/* Shared browser runtime target validation. Never logs configuration values. */
(function attachHrRuntimeConfigResolver(root) {
    function publicKeyMatchesProject(key, projectRef) {
        if (typeof key !== 'string') return false;
        const parts = key.split('.');
        if (parts.length !== 3) return false;
        try {
            const normalized = parts[1].replace(/-/g, '+').replace(/_/g, '/');
            const payload = JSON.parse(root.atob(normalized + '='.repeat((4 - normalized.length % 4) % 4)));
            return payload.ref === projectRef && payload.role === 'anon';
        } catch (_) {
            return false;
        }
    }

    function resolveHrSupabaseRuntimeConfig(config, options) {
        const settings = options || {};
        const production = settings.production || {};
        const staging = settings.staging || {};
        const allowedModes = Array.isArray(settings.allowedModes) ? settings.allowedModes : [];
        const invalid = { valid: false, mode: null, supabaseUrl: null, anonKey: null, error: 'Supabase runtime configuration is missing, invalid, or mismatched.' };
        if (!config || typeof config !== 'object' || Array.isArray(config)) return invalid;

        const mode = config.mode;
        if (!allowedModes.includes(mode) || config.valid !== true || config.error != null) return invalid;
        const allowedFields = new Set(['mode', 'valid', 'projectRef', 'supabaseUrl', 'anonKey']);
        if (Object.keys(config).some(field => !allowedFields.has(field))) return invalid;

        if (mode === 'production') {
            if (config.projectRef !== production.projectRef || config.supabaseUrl !== production.supabaseUrl) return invalid;
            if (!publicKeyMatchesProject(production.anonKey, production.projectRef)) return invalid;
            if (config.anonKey !== undefined && (config.anonKey !== production.anonKey || !publicKeyMatchesProject(config.anonKey, production.projectRef))) return invalid;
            return { valid: true, mode, supabaseUrl: production.supabaseUrl, anonKey: production.anonKey, error: null };
        }

        if (mode === 'staging') {
            if (!staging.projectRef || config.projectRef !== staging.projectRef || config.supabaseUrl !== staging.supabaseUrl) return invalid;
            if (!publicKeyMatchesProject(config.anonKey, staging.projectRef)) return invalid;
            return { valid: true, mode, supabaseUrl: staging.supabaseUrl, anonKey: config.anonKey, error: null };
        }

        return invalid;
    }

    root.hrResolveSupabaseRuntimeConfig = resolveHrSupabaseRuntimeConfig;
    if (typeof module !== 'undefined' && module.exports) module.exports = { resolveHrSupabaseRuntimeConfig };
})(typeof window !== 'undefined' ? window : globalThis);
