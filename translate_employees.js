async function translateEmployeeNames() {
    console.log("Starting batch translation of employee names...");
    const { data: profiles, error: fetchError } = await window.supabaseClient
        .from('profiles')
        .select('*');

    if (fetchError) {
        console.error("Failed to fetch profiles:", fetchError);
        return;
    }

    console.log(`Found ${profiles.length} profiles to process.`);
    
    let updatedCount = 0;
    for (const profile of profiles) {
        // Skip if they already have an Arabic name or don't have a display name
        if (profile.display_name_ar || !profile.display_name) {
            continue;
        }

        try {
            const res = await fetch(`https://translate.googleapis.com/translate_a/single?client=gtx&sl=en&tl=ar&dt=t&q=${encodeURIComponent(profile.display_name)}`);
            const data = await res.json();
            const translatedName = data[0].map(x => x[0]).join('');

            console.log(`Translating: ${profile.display_name} -> ${translatedName}`);

            const { error: updateError } = await window.supabaseClient
                .from('profiles')
                .update({ display_name_ar: translatedName })
                .eq('id', profile.id);

            if (updateError) {
                console.error(`Failed to update ${profile.display_name}:`, updateError);
            } else {
                updatedCount++;
            }
            // Small delay to avoid rate limiting
            await new Promise(r => setTimeout(r, 500));
        } catch (err) {
            console.error(`Error translating ${profile.display_name}:`, err);
        }
    }

    console.log(`Finished batch translation. Successfully updated ${updatedCount} profiles.`);
}

// Run the function
translateEmployeeNames();
