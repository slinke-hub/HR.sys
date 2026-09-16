// Phase 1 Mock Data for WhatsApp Inbox
window.WhatsAppMockData = {
    contacts: [
        { id: 'c1', name: 'Mohammed Al-Harbi', phone: '+966501234567', company: 'Global Events Co', tags: ['VIP', 'Event Planning'], assigned_to: 'u1', linked_client_id: 12 },
        { id: 'c2', name: 'Sarah Khalid', phone: '+966551234567', company: 'Tech Solutions', tags: ['New Client'], assigned_to: 'u2', linked_client_id: null },
        { id: 'c3', name: 'Ahmed Abdullah', phone: '+966591234567', company: '', tags: [], assigned_to: null, linked_client_id: null },
        { id: 'c4', name: 'Noura Al-Saud', phone: '+966561234567', company: 'Royal Exhibitions', tags: ['Enterprise'], assigned_to: 'u1', linked_client_id: 45 }
    ],
    conversations: [
        { id: 'conv1', contact_id: 'c1', linked_project_id: 8, assigned_user_id: 'u1', status: 'In Progress', last_message_at: new Date(Date.now() - 1000 * 60 * 5).toISOString(), unread_count: 2 },
        { id: 'conv2', contact_id: 'c2', linked_project_id: null, assigned_user_id: 'u2', status: 'New', last_message_at: new Date(Date.now() - 1000 * 60 * 30).toISOString(), unread_count: 1 },
        { id: 'conv3', contact_id: 'c3', linked_project_id: null, assigned_user_id: null, status: 'Waiting for Client', last_message_at: new Date(Date.now() - 1000 * 60 * 60 * 2).toISOString(), unread_count: 0 },
        { id: 'conv4', contact_id: 'c4', linked_project_id: 12, assigned_user_id: 'u1', status: 'Closed', last_message_at: new Date(Date.now() - 1000 * 60 * 60 * 24 * 2).toISOString(), unread_count: 0 }
    ],
    messages: [
        // Conversation 1
        { id: 'm1', conversation_id: 'conv1', direction: 'in', type: 'text', text: 'Hello, I need a quotation for the upcoming corporate event.', sent_at: new Date(Date.now() - 1000 * 60 * 60 * 24).toISOString(), status: 'read' },
        { id: 'm2', conversation_id: 'conv1', direction: 'out', type: 'text', text: 'Hi Mohammed, sure thing. Do you have the venue dimensions?', sent_at: new Date(Date.now() - 1000 * 60 * 60 * 23).toISOString(), status: 'read' },
        { id: 'm3', conversation_id: 'conv1', direction: 'in', type: 'text', text: 'Can we change the backdrop to 3m × 2.5m?', sent_at: new Date(Date.now() - 1000 * 60 * 6).toISOString(), status: 'delivered' },
        { id: 'm4', conversation_id: 'conv1', direction: 'in', type: 'text', text: 'Also, please add a 4x3 LED screen.', sent_at: new Date(Date.now() - 1000 * 60 * 5).toISOString(), status: 'delivered' },
        // Conversation 2
        { id: 'm5', conversation_id: 'conv2', direction: 'in', type: 'text', text: 'Hello, we are looking for a venue for a tech conference.', sent_at: new Date(Date.now() - 1000 * 60 * 30).toISOString(), status: 'delivered' },
        // Conversation 3
        { id: 'm6', conversation_id: 'conv3', direction: 'in', type: 'text', text: 'Please send the venue location.', sent_at: new Date(Date.now() - 1000 * 60 * 60 * 3).toISOString(), status: 'read' },
        { id: 'm7', conversation_id: 'conv3', direction: 'out', type: 'text', text: 'Here is the location pin.', sent_at: new Date(Date.now() - 1000 * 60 * 60 * 2.5).toISOString(), status: 'read' },
        // Conversation 4
        { id: 'm8', conversation_id: 'conv4', direction: 'out', type: 'document', text: 'Revised Quotation.pdf', media_url: '#', sent_at: new Date(Date.now() - 1000 * 60 * 60 * 24 * 3).toISOString(), status: 'read' },
        { id: 'm9', conversation_id: 'conv4', direction: 'in', type: 'text', text: 'Looks perfect. I approve the design and quotation.', sent_at: new Date(Date.now() - 1000 * 60 * 60 * 24 * 2).toISOString(), status: 'read' }
    ],
    internal_notes: [
        { id: 'n1', conversation_id: 'conv1', user_id: 'u1', note: 'Client is strict on budget. Ensure LED screen is priced competitively.', created_at: new Date(Date.now() - 1000 * 60 * 4).toISOString() }
    ],
    projects: [
        { id: 8, name: 'Corporate Event 2026', date: '15 March 2026', venue: 'Riyadh Exhibition Centre', status: 'In Progress' },
        { id: 12, name: 'Royal Gala Dinner', date: '10 Feb 2026', venue: 'Four Seasons', status: 'Completed' }
    ],
    users: [
        { id: 'u1', name: 'Admin User', role: 'Admin' },
        { id: 'u2', name: 'Sales Rep 1', role: 'Employee' }
    ]
};
