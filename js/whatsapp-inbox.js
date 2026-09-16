// WhatsApp Inbox Beta - Phase 1 Logic

(function() {
    // 1. Initialization and Beta Flag Management
    window.toggleWhatsappBeta = function(enabled) {
        localStorage.setItem('whatsapp_inbox_beta', enabled ? 'true' : 'false');
        
        // Show/hide sidebar item
        const nav = document.getElementById('navWhatsAppBeta');
        if (nav) {
            nav.style.display = enabled ? 'flex' : 'none';
        }
        
        // If disabled while on the view, redirect to dashboard
        if (!enabled && window.currentView === 'whatsapp_inbox') {
            window.renderView('dashboard');
        }
        
        // Update checkbox if it exists on the integrations page
        const checkbox = document.getElementById('settingWhatsappBetaEnabled');
        if (checkbox) {
            checkbox.checked = enabled;
        }
    };

    // Apply on load
    document.addEventListener('DOMContentLoaded', () => {
        const isBetaEnabled = localStorage.getItem('whatsapp_inbox_beta') === 'true';
        if (isBetaEnabled) {
            const nav = document.getElementById('navWhatsAppBeta');
            if (nav) nav.style.display = 'flex';
        }
    });

    // 2. View Rendering
    let currentConversationId = null;
    let searchQuery = '';
    let filterStatus = 'All';

    window.renderWhatsAppInbox = async function() {
        // Validate access
        if (localStorage.getItem('whatsapp_inbox_beta') !== 'true') {
            return `<div class="page-header"><h1 class="page-title">${window.t ? window.t('ui_unauthorized') : 'Unauthorized'}</h1></div>`;
        }

        const data = window.WhatsAppMockData;
        const conversations = data.conversations.filter(c => {
            if (filterStatus !== 'All' && c.status !== filterStatus) return false;
            
            const contact = data.contacts.find(con => con.id === c.contact_id);
            if (searchQuery && contact && !contact.name.toLowerCase().includes(searchQuery.toLowerCase()) && !contact.phone.includes(searchQuery)) {
                return false;
            }
            
            return true;
        });

        // 3-Column Layout
        return `
            <div class="whatsapp-inbox-container" style="display:flex; height: calc(100vh - 80px); background: var(--color-surface); border: 1px solid var(--color-border); border-radius: 12px; overflow: hidden;">
                
                <!-- LEFT COLUMN: Conversations List -->
                <div class="whatsapp-conversations-list" style="width: 320px; border-right: 1px solid var(--color-border); display:flex; flex-direction:column;">
                    <div style="padding: 1rem; border-bottom: 1px solid var(--color-border); background: var(--color-surface-hover);">
                        <h3 style="margin: 0 0 1rem 0; display:flex; align-items:center; gap:0.5rem;"><i data-lucide="message-circle"></i> Inbox <small class="nav-beta-badge" style="position:static;">BETA</small></h3>
                        <input type="text" id="waSearchInput" placeholder="Search chats..." class="form-control" style="margin-bottom: 0.5rem;" value="${searchQuery}" onkeyup="if(event.key==='Enter') window.waSearch(this.value)">
                        <select id="waStatusFilter" class="form-control" onchange="window.waFilter(this.value)">
                            <option value="All" ${filterStatus === 'All' ? 'selected' : ''}>All</option>
                            <option value="New" ${filterStatus === 'New' ? 'selected' : ''}>New</option>
                            <option value="In Progress" ${filterStatus === 'In Progress' ? 'selected' : ''}>In Progress</option>
                            <option value="Waiting for Client" ${filterStatus === 'Waiting for Client' ? 'selected' : ''}>Waiting for Client</option>
                            <option value="Closed" ${filterStatus === 'Closed' ? 'selected' : ''}>Closed</option>
                        </select>
                    </div>
                    <div style="flex:1; overflow-y:auto;">
                        ${conversations.map(c => {
                            const contact = data.contacts.find(con => con.id === c.contact_id);
                            const lastMsgDate = new Date(c.last_message_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                            return `
                            <div onclick="window.waSelectConversation('${c.id}')" style="padding: 1rem; border-bottom: 1px solid var(--color-border); cursor:pointer; background: ${currentConversationId === c.id ? 'var(--color-surface-hover)' : 'transparent'};">
                                <div style="display:flex; justify-content:space-between; margin-bottom: 0.25rem;">
                                    <strong style="font-size:0.95rem;">${contact ? contact.name : 'Unknown'}</strong>
                                    <span style="font-size:0.75rem; color: var(--color-text-secondary);">${lastMsgDate}</span>
                                </div>
                                <div style="display:flex; justify-content:space-between; align-items:center;">
                                    <span style="font-size:0.85rem; color: var(--color-text-secondary); text-overflow:ellipsis; white-space:nowrap; overflow:hidden;">Status: ${c.status}</span>
                                    ${c.unread_count > 0 ? `<span style="background: var(--color-primary); color: white; border-radius: 50%; width: 20px; height: 20px; display:inline-flex; align-items:center; justify-content:center; font-size: 0.7rem;">${c.unread_count}</span>` : ''}
                                </div>
                            </div>
                            `;
                        }).join('')}
                        ${conversations.length === 0 ? '<div style="padding:2rem; text-align:center; color:var(--color-text-secondary);">No conversations found.</div>' : ''}
                    </div>
                </div>

                <!-- CENTER COLUMN: Chat Window -->
                <div class="whatsapp-chat-window" style="flex:1; display:flex; flex-direction:column; background: var(--color-background);">
                    ${currentConversationId ? window.waRenderChatWindow(currentConversationId) : `
                        <div style="flex:1; display:flex; flex-direction:column; justify-content:center; align-items:center; color: var(--color-text-secondary);">
                            <i data-lucide="message-square" style="width: 64px; height: 64px; margin-bottom: 1rem; opacity: 0.5;"></i>
                            <h2>WhatsApp Inbox Beta</h2>
                            <p>Select a conversation to start messaging</p>
                            <div style="margin-top:2rem; padding: 1rem; background: var(--color-surface-hover); border-radius: 8px; border: 1px dashed var(--color-border); max-width: 400px; text-align:center;">
                                <strong>DEMO DATA ONLY</strong><br>
                                No real WhatsApp messages will be sent during this beta test.
                            </div>
                        </div>
                    `}
                </div>

                <!-- RIGHT COLUMN: Contact Panel -->
                ${currentConversationId ? window.waRenderContactPanel(currentConversationId) : ''}
            </div>
        `;
    };

    window.waRenderChatWindow = function(convId) {
        const data = window.WhatsAppMockData;
        const conv = data.conversations.find(c => c.id === convId);
        const contact = data.contacts.find(c => c.id === conv.contact_id);
        const messages = data.messages.filter(m => m.conversation_id === convId).sort((a,b) => new Date(a.sent_at) - new Date(b.sent_at));
        const notes = data.internal_notes.filter(n => n.conversation_id === convId);

        // Interleave messages and notes
        const allItems = [...messages, ...notes.map(n => ({...n, type: 'internal_note'}))];
        allItems.sort((a,b) => new Date(a.sent_at || a.created_at) - new Date(b.sent_at || b.created_at));

        return `
            <div style="padding: 1rem; background: var(--color-surface); border-bottom: 1px solid var(--color-border); display:flex; justify-content:space-between; align-items:center;">
                <div style="display:flex; align-items:center; gap: 1rem;">
                    <div style="width: 40px; height: 40px; border-radius: 50%; background: var(--color-primary); color:white; display:flex; align-items:center; justify-content:center; font-weight:bold;">
                        ${contact.name.charAt(0)}
                    </div>
                    <div>
                        <div style="font-weight:600;">${contact.name}</div>
                        <div style="font-size:0.8rem; color: var(--color-text-secondary);">${contact.phone}</div>
                    </div>
                </div>
                <div>
                    <span class="status-badge info">${conv.status}</span>
                </div>
            </div>
            
            <div style="flex:1; overflow-y:auto; padding: 1.5rem; display:flex; flex-direction:column; gap: 1rem;">
                ${allItems.map(item => {
                    const time = new Date(item.sent_at || item.created_at).toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
                    
                    if (item.type === 'internal_note') {
                        return `
                            <div style="align-self: center; background: #fff3cd; color: #856404; padding: 0.5rem 1rem; border-radius: 16px; font-size: 0.85rem; max-width: 80%; border: 1px solid #ffeeba;">
                                <strong>Internal Note:</strong> ${item.note}
                                <div style="text-align:right; font-size:0.7rem; margin-top:4px; opacity:0.8;">${time}</div>
                            </div>
                        `;
                    }
                    
                    const isOut = item.direction === 'out';
                    const align = isOut ? 'flex-end' : 'flex-start';
                    const bg = isOut ? 'var(--color-primary)' : 'var(--color-surface)';
                    const color = isOut ? 'white' : 'var(--color-text)';
                    const border = isOut ? 'none' : '1px solid var(--color-border)';

                    return `
                        <div style="align-self: ${align}; max-width: 70%; display:flex; flex-direction:column;">
                            <div style="background: ${bg}; color: ${color}; padding: 0.75rem 1rem; border-radius: 12px; border: ${border}; box-shadow: 0 1px 2px rgba(0,0,0,0.05);">
                                ${item.type === 'document' ? `<div style="display:flex;align-items:center;gap:0.5rem;"><i data-lucide="file-text"></i> ${item.text}</div>` : item.text}
                            </div>
                            <div style="display:flex; justify-content: ${isOut ? 'flex-end' : 'flex-start'}; gap: 0.5rem; margin-top: 0.25rem; font-size: 0.75rem; color: var(--color-text-secondary);">
                                <span>${time}</span>
                                ${isOut ? `<span>${item.status === 'read' ? '✓✓' : (item.status === 'delivered' ? '✓' : '...')}</span>` : ''}
                            </div>
                            ${!isOut ? `<div style="font-size:0.75rem; margin-top: 4px;"><a href="#" onclick="window.waCreateTaskFromMsg('${item.text}')" style="color:var(--color-primary);">Create Task</a></div>` : ''}
                        </div>
                    `;
                }).join('')}
            </div>
            
            <div style="padding: 1rem; background: var(--color-surface); border-top: 1px solid var(--color-border);">
                <div style="display:flex; gap: 0.5rem;">
                    <button class="icon-btn" title="Attach file"><i data-lucide="paperclip"></i></button>
                    <input type="text" id="waMessageInput" class="form-control" placeholder="Type a message..." style="flex:1;" onkeyup="if(event.key==='Enter') window.waSendMessage()">
                    <button class="btn btn-primary" onclick="window.waSendMessage()"><i data-lucide="send"></i></button>
                </div>
            </div>
        `;
    };

    window.waRenderContactPanel = function(convId) {
        const data = window.WhatsAppMockData;
        const conv = data.conversations.find(c => c.id === convId);
        const contact = data.contacts.find(c => c.id === conv.contact_id);
        const project = conv.linked_project_id ? data.projects.find(p => p.id === conv.linked_project_id) : null;
        
        return `
            <div class="whatsapp-contact-panel" style="width: 300px; border-left: 1px solid var(--color-border); background: var(--color-surface); display:flex; flex-direction:column; overflow-y:auto; padding: 1.5rem;">
                <h4 style="margin-top:0; margin-bottom:1.5rem; border-bottom:1px solid var(--color-border); padding-bottom:0.5rem;">Contact Details</h4>
                
                <div style="margin-bottom: 1.5rem;">
                    <strong>Name:</strong> ${contact.name}<br>
                    <strong>Phone:</strong> ${contact.phone}<br>
                    <strong>Company:</strong> ${contact.company || 'N/A'}
                </div>

                <div style="margin-bottom: 1.5rem;">
                    <strong>Tags:</strong><br>
                    ${contact.tags.length ? contact.tags.map(t => `<span class="status-badge" style="margin-top:0.25rem;">${t}</span>`).join(' ') : 'None'}
                </div>

                <h4 style="margin-top:1rem; margin-bottom:1rem; border-bottom:1px solid var(--color-border); padding-bottom:0.5rem;">Linked Project</h4>
                ${project ? `
                    <div class="card" style="padding: 1rem; margin-bottom:1rem;">
                        <strong style="display:block;margin-bottom:0.25rem;">${project.name}</strong>
                        <div style="font-size:0.8rem; color:var(--color-text-secondary); margin-bottom:0.25rem;"><i data-lucide="calendar" style="width:14px;height:14px;"></i> ${project.date}</div>
                        <div style="font-size:0.8rem; color:var(--color-text-secondary);"><i data-lucide="map-pin" style="width:14px;height:14px;"></i> ${project.venue}</div>
                    </div>
                ` : `
                    <div style="margin-bottom:1rem; color:var(--color-text-secondary); font-size:0.9rem;">No project linked.</div>
                    <button class="btn btn-secondary btn-sm" style="width:100%; margin-bottom: 0.5rem;" onclick="alert('Demo: Opening create project modal')">Create Project</button>
                    <button class="btn btn-secondary btn-sm" style="width:100%;">Link Existing Project</button>
                `}

                <h4 style="margin-top:1.5rem; margin-bottom:1rem; border-bottom:1px solid var(--color-border); padding-bottom:0.5rem;">Quick Actions</h4>
                <div style="display:flex; flex-direction:column; gap: 0.5rem;">
                    <button class="btn btn-secondary" onclick="window.waCreateTaskFromMsg('General Task from WhatsApp')"><i data-lucide="check-square"></i> Create Task</button>
                    <button class="btn btn-secondary" onclick="alert('Demo: Create Quotation')"><i data-lucide="file-text"></i> Create Quotation</button>
                    <button class="btn btn-secondary" onclick="window.waAddInternalNote()"><i data-lucide="sticky-note"></i> Add Internal Note</button>
                </div>
            </div>
        `;
    };

    // Actions
    window.waSearch = function(query) {
        searchQuery = query;
        if(window.renderView) window.renderView('whatsapp_inbox');
    };

    window.waFilter = function(status) {
        filterStatus = status;
        if(window.renderView) window.renderView('whatsapp_inbox');
    };

    window.waSelectConversation = function(id) {
        currentConversationId = id;
        
        // Mark as read in mock data
        const conv = window.WhatsAppMockData.conversations.find(c => c.id === id);
        if(conv) conv.unread_count = 0;
        
        if(window.renderView) window.renderView('whatsapp_inbox');
    };

    window.waSendMessage = function() {
        const input = document.getElementById('waMessageInput');
        const text = input.value.trim();
        if(!text || !currentConversationId) return;

        window.WhatsAppMockData.messages.push({
            id: 'm' + Date.now(),
            conversation_id: currentConversationId,
            direction: 'out',
            type: 'text',
            text: text,
            sent_at: new Date().toISOString(),
            status: 'delivered'
        });
        
        const conv = window.WhatsAppMockData.conversations.find(c => c.id === currentConversationId);
        if(conv) conv.last_message_at = new Date().toISOString();

        input.value = '';
        if(window.renderView) window.renderView('whatsapp_inbox');
    };

    window.waAddInternalNote = function() {
        const note = prompt("Enter internal note (visible to team only):");
        if(note && note.trim() && currentConversationId) {
            window.WhatsAppMockData.internal_notes.push({
                id: 'n' + Date.now(),
                conversation_id: currentConversationId,
                user_id: 'u1',
                note: note.trim(),
                created_at: new Date().toISOString()
            });
            if(window.renderView) window.renderView('whatsapp_inbox');
        }
    };

    window.waCreateTaskFromMsg = function(msgText) {
        // Find existing task modal elements and trigger them to show we integrate properly
        const titleInput = document.getElementById('taskTitle');
        const descInput = document.getElementById('taskDescription');
        
        if(titleInput) titleInput.value = "Follow up: WhatsApp Request";
        if(descInput) descInput.value = "Source: WhatsApp\\n\\nMessage: " + msgText;
        
        // Open the task modal
        if (typeof window.showTaskSidePanel === 'function') {
            window.showTaskSidePanel();
        } else {
            alert('Demo: Task created with description: ' + msgText);
        }
    };

})();
