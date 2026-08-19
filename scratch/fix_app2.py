import sys

with open('e:/HR.sys/js/app.js', 'r', encoding='utf-8') as f:
    content = f.read()

target = '''                <div style="text-align: right; margin-bottom: 1.5rem;">
    }

    // News Hub'''

replacement = '''                <div style="text-align: right; margin-bottom: 1.5rem;">
                    <a href="#" onclick="setLoginMode('forgot')" style="color: white; font-size: 0.85rem; text-decoration: none;">${t('forgot_password')}</a>
                </div>
                <button type="submit" class="btn-primary" style="width: 100%; padding: 0.875rem; font-size: 1rem;">${t('sign_in')}</button>
            </form>
        `;
    }

    return `
        <div style="display: flex; height: 100vh; align-items: center; justify-content: center; width: 100vw; position: fixed; top: 0; left: 0; background: url('images/login_bg.png') center/cover no-repeat; z-index: 9999;">
            <div class="card" style="width: 100%; max-width: 400px; padding: 2.5rem 2rem; background: rgba(0, 0, 0, 0.4); backdrop-filter: blur(12px); -webkit-backdrop-filter: blur(12px); border: 1px solid rgba(255, 255, 255, 0.2); box-shadow: 0 30px 60px rgba(0,0,0,0.3); color: white;">
                ${formHTML}
            </div>
            
            <div style="position: absolute; top: 20px; right: 20px; display: flex; gap: 10px; z-index: 10000;">
                <button class="icon-btn" onclick="toggleLanguage()">
                    <i data-lucide="globe"></i> <span id="langText" style="font-size: 0.875rem; font-weight: 600; margin-inline-start: 4px;">${currentLang === 'en' ? 'AR' : 'EN'}</span>
                </button>
                <button class="icon-btn" onclick="toggleTheme()">
                    <i id="themeIcon" data-lucide="${currentTheme === 'light' ? 'moon' : 'sun'}"></i>
                </button>
            </div>
        </div>
    `;
}

async function renderDashboard() {
    const newsQuery = currentLang === 'ar' ? '"السعودية" (أعمال OR "نظام العمل")' : '"Saudi Arabia" (business OR "labor law" OR "labour law")';
    const newsHl = currentLang === 'ar' ? 'ar' : 'en-US';
    const newsGl = currentLang === 'ar' ? 'SA' : 'US';
    const newsCeid = currentLang === 'ar' ? 'SA:ar' : 'US:en';
    const rssUrl = `https://news.google.com/rss/search?q=${encodeURIComponent(newsQuery)}&hl=${newsHl}&gl=${newsGl}&ceid=${newsCeid}`;
    const newsApiUrl = `https://api.rss2json.com/v1/api.json?rss_url=${encodeURIComponent(rssUrl)}`;

    // Run independent fetches in parallel
    const [todayAttendance, announcements, newsRes, profile] = await Promise.all([
        db.fetchTodayAttendance(currentUser?.id),
        db.fetchAnnouncements(),
        fetch(newsApiUrl).catch(() => null),
        db.getUserProfile(currentUser?.id)
    ]);

    const isClockedIn = todayAttendance != null && !todayAttendance.clock_out_time;
    const announcementsList = announcements || [];
    const dashboardName = getProfileDisplayName(profile);
    const welcomeMessage = t('welcome').replace('{name}', escapeHTML(dashboardName));

    let announcementsHTML = announcementsList.map(a => `
        <div class="announcement-item">
            <div class="announcement-icon" style="background: rgba(16, 185, 129, 0.1); color: var(--color-success);">
                <i data-lucide="megaphone"></i>
            </div>
            <div class="announcement-content">
                <h4>${escapeHTML(a.title)}</h4>
                <p>${escapeHTML(a.content)}</p>
                <small style="color:var(--color-text-secondary);">${new Date(a.created_at).toLocaleDateString()}</small>
            </div>
        </div>
    `).join('');
    if (announcementsList.length === 0) {
        announcementsHTML = \`<p style="color: var(--color-text-secondary); padding: 1rem 0;">\${t('dash_no_announcements')}</p>\`;
    }

    // News Hub'''

if target in content:
    content = content.replace(target, replacement)
    with open('e:/HR.sys/js/app.js', 'w', encoding='utf-8') as f:
        f.write(content)
    print('Successfully patched app.js')
else:
    print('Target string not found in app.js')
