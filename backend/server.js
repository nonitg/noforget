require('dotenv').config();
const express = require('express');
const twilio = require('twilio');

const app = express();
app.use(express.json());
app.use(express.urlencoded({ extended: true })); // For Twilio webhooks

// Environment variables
const accountSid = process.env.TWILIO_ACCOUNT_SID;
const authToken = process.env.TWILIO_AUTH_TOKEN;
const twilioNumber = process.env.TWILIO_PHONE_NUMBER;
const baseUrl = process.env.BASE_URL || 'http://localhost:3000';

// Validate required environment variables
if (!accountSid || !authToken || !twilioNumber) {
    console.error('Missing required Twilio credentials. Please set:');
    console.error('  TWILIO_ACCOUNT_SID');
    console.error('  TWILIO_AUTH_TOKEN');
    console.error('  TWILIO_PHONE_NUMBER');
    process.exit(1);
}

const client = twilio(accountSid, authToken);

// ============================================
// STORAGE WITH AUTOMATIC CLEANUP
// ============================================

// In-memory storage for scheduled calls
// Note: This resets if server restarts. For production, use a database.
const scheduledCalls = new Map();
const activeCalls = new Map();

// Constants for cleanup
const MAX_SCHEDULED_CALLS = 1000;  // Prevent unbounded growth
const MAX_ACTIVE_CALLS = 500;
const CLEANUP_INTERVAL = 5 * 60 * 1000;  // Run cleanup every 5 minutes
const SCHEDULED_CALL_MAX_AGE = 24 * 60 * 60 * 1000;  // Remove scheduled calls older than 24 hours
const ACTIVE_CALL_MAX_AGE = 2 * 60 * 60 * 1000;  // Remove active calls older than 2 hours

// ============================================
// CLEANUP FUNCTIONS
// ============================================

function cleanupScheduledCalls() {
    const now = Date.now();
    let removed = 0;

    for (const [id, scheduled] of scheduledCalls.entries()) {
        // Remove if:
        // 1. Already called and older than 1 hour
        // 2. Older than 24 hours (regardless of status)
        // 3. Failed calls older than 1 hour
        const age = now - scheduled.callAt;
        const shouldRemove =
            (scheduled.called && age > 60 * 60 * 1000) ||
            (age > SCHEDULED_CALL_MAX_AGE) ||
            (scheduled.status === 'failed' && age > 60 * 60 * 1000);

        if (shouldRemove) {
            scheduledCalls.delete(id);
            removed++;
        }
    }

    if (removed > 0) {
        console.log(`🧹 Cleaned up ${removed} old scheduled calls. Remaining: ${scheduledCalls.size}`);
    }
}

function cleanupActiveCalls() {
    const now = Date.now();
    let removed = 0;

    for (const [callSid, callInfo] of activeCalls.entries()) {
        const createdAt = new Date(callInfo.createdAt).getTime();
        const age = now - createdAt;

        // Remove calls older than 2 hours
        if (age > ACTIVE_CALL_MAX_AGE) {
            activeCalls.delete(callSid);
            removed++;
        }
    }

    if (removed > 0) {
        console.log(`🧹 Cleaned up ${removed} old active calls. Remaining: ${activeCalls.size}`);
    }
}

function enforceMaxSize() {
    // If we have too many scheduled calls, remove oldest completed ones first
    if (scheduledCalls.size > MAX_SCHEDULED_CALLS) {
        const sorted = Array.from(scheduledCalls.entries())
            .filter(([_, s]) => s.called)  // Prioritize removing completed
            .sort((a, b) => a[1].callAt - b[1].callAt);  // Oldest first

        const toRemove = scheduledCalls.size - MAX_SCHEDULED_CALLS;
        for (let i = 0; i < toRemove && i < sorted.length; i++) {
            scheduledCalls.delete(sorted[i][0]);
        }
        console.log(`⚠️ Enforced max scheduled calls limit. Size: ${scheduledCalls.size}`);
    }

    // Same for active calls
    if (activeCalls.size > MAX_ACTIVE_CALLS) {
        const sorted = Array.from(activeCalls.entries())
            .sort((a, b) => new Date(a[1].createdAt) - new Date(b[1].createdAt));

        const toRemove = activeCalls.size - MAX_ACTIVE_CALLS;
        for (let i = 0; i < toRemove; i++) {
            activeCalls.delete(sorted[i][0]);
        }
        console.log(`⚠️ Enforced max active calls limit. Size: ${activeCalls.size}`);
    }
}

// Run periodic cleanup
setInterval(() => {
    cleanupScheduledCalls();
    cleanupActiveCalls();
    enforceMaxSize();
}, CLEANUP_INTERVAL);

// ============================================
// SCHEDULER - Checks every 30 seconds for due calls
// ============================================
function checkScheduledCalls() {
    const now = Date.now();

    for (const [id, scheduled] of scheduledCalls.entries()) {
        if (scheduled.callAt <= now && !scheduled.called) {
            console.log(`⏰ Time to call for reminder: ${scheduled.reminderTitle}`);

            // Mark as called IMMEDIATELY to prevent duplicate calls
            scheduled.called = true;
            scheduled.status = 'calling';
            scheduled.calledAt = new Date().toISOString();

            // Initiate the call
            initiateScheduledCall(scheduled)
                .then(callSid => {
                    scheduled.callSid = callSid;
                    scheduled.status = 'initiated';
                    console.log(`✅ Call initiated: ${callSid}`);
                })
                .catch(error => {
                    scheduled.status = 'failed';
                    scheduled.error = error.message;
                    console.error(`❌ Call failed: ${error.message}`);
                });
        }
    }
}

// Run scheduler every 30 seconds
const schedulerInterval = setInterval(checkScheduledCalls, 30000);
console.log('📅 Call scheduler started (checking every 30 seconds)');

// Also check immediately on health requests (in case server was sleeping)
function ensureSchedulerRunning() {
    checkScheduledCalls();
}

// ============================================
// HELPER: Initiate a scheduled call
// ============================================
async function initiateScheduledCall(scheduled) {
    const { to, reminderTitle, reminderDescription, dueTime } = scheduled;

    const call = await client.calls.create({
        to: to,
        from: twilioNumber,
        twiml: generateTwiML(reminderTitle, reminderDescription, dueTime),
        statusCallback: `${baseUrl}/status`,
        statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'],
        statusCallbackMethod: 'POST'
    });

    // Store call info with reference to scheduled call
    activeCalls.set(call.sid, {
        to,
        reminderTitle,
        scheduledId: scheduled.id,
        status: call.status,
        createdAt: new Date().toISOString()
    });

    return call.sid;
}

// ============================================
// HELPER: Generate TwiML for call
// ============================================
function generateTwiML(reminderTitle, reminderDescription, dueTime) {
    return `
        <Response>
            <Say voice="Polly.Joanna" language="en-US">
                <prosody rate="95%">
                    Attention! This is your NoForget reminder.
                </prosody>
            </Say>
            <Pause length="0.5"/>
            <Say voice="Polly.Joanna" language="en-US">
                <prosody rate="90%">
                    ${escapeXml(reminderTitle)}.
                </prosody>
            </Say>
            ${reminderDescription ? `
            <Pause length="0.3"/>
            <Say voice="Polly.Joanna" language="en-US">
                ${escapeXml(reminderDescription)}
            </Say>
            ` : ''}
            <Pause length="0.5"/>
            <Say voice="Polly.Joanna" language="en-US">
                This was scheduled for ${escapeXml(dueTime || 'now')}.
            </Say>
            <Pause length="1"/>
            <Say voice="Polly.Joanna" language="en-US">
                Press 1 to confirm you received this reminder.
                Press 2 to be called again in 5 minutes.
            </Say>
            <Gather numDigits="1" action="${baseUrl}/gather" method="POST" timeout="10">
                <Say voice="Polly.Joanna">Waiting for your response.</Say>
            </Gather>
            <Say voice="Polly.Joanna" language="en-US">
                No response received. Goodbye.
            </Say>
        </Response>
    `;
}

// ============================================
// ENDPOINTS
// ============================================

// Health check endpoint
app.get('/health', (req, res) => {
    ensureSchedulerRunning();
    res.json({
        status: 'ok',
        timestamp: new Date().toISOString(),
        scheduledCalls: scheduledCalls.size,
        activeCalls: activeCalls.size,
        uptime: Math.floor(process.uptime()) + 's'
    });
});

// App info endpoint - provides Twilio number for onboarding
app.get('/info', (req, res) => {
    res.json({
        twilioNumber: twilioNumber,
        appName: 'NoForget',
        contactName: 'Remind Line'
    });
});

// ============================================
// PHONE VERIFICATION (Twilio Verify)
// ============================================

// Send verification code via SMS
app.post('/verify/send', async (req, res) => {
    try {
        const { phoneNumber } = req.body;

        if (!phoneNumber) {
            return res.status(400).json({ error: 'Phone number is required' });
        }

        const verifyServiceSid = process.env.TWILIO_VERIFY_SERVICE_SID;
        if (!verifyServiceSid) {
            return res.status(500).json({ error: 'Verification service not configured' });
        }

        const verification = await client.verify.v2
            .services(verifyServiceSid)
            .verifications.create({
                to: phoneNumber,
                channel: 'sms'
            });

        console.log(`📱 Verification sent to ${phoneNumber}: ${verification.status}`);

        res.json({
            status: verification.status,
            message: 'Verification code sent'
        });

    } catch (error) {
        console.error('Error sending verification:', error);
        res.status(500).json({
            error: 'Failed to send verification',
            message: error.message
        });
    }
});

// Check verification code
app.post('/verify/check', async (req, res) => {
    try {
        const { phoneNumber, code } = req.body;

        if (!phoneNumber || !code) {
            return res.status(400).json({ error: 'Phone number and code are required' });
        }

        const verifyServiceSid = process.env.TWILIO_VERIFY_SERVICE_SID;
        if (!verifyServiceSid) {
            return res.status(500).json({ error: 'Verification service not configured' });
        }

        const verificationCheck = await client.verify.v2
            .services(verifyServiceSid)
            .verificationChecks.create({
                to: phoneNumber,
                code: code
            });

        console.log(`✅ Verification check for ${phoneNumber}: ${verificationCheck.status}`);

        res.json({
            status: verificationCheck.status,
            valid: verificationCheck.status === 'approved'
        });

    } catch (error) {
        console.error('Error checking verification:', error);

        // Handle specific Twilio errors
        if (error.code === 20404) {
            return res.status(400).json({
                error: 'Invalid or expired code',
                valid: false
            });
        }

        res.status(500).json({
            error: 'Failed to check verification',
            message: error.message,
            valid: false
        });
    }
});

// Schedule a call for later
app.post('/schedule', async (req, res) => {
    try {
        const { to, reminderTitle, reminderDescription, callAt, reminderId } = req.body;

        if (!to) {
            return res.status(400).json({ error: 'Phone number (to) is required' });
        }

        if (!reminderTitle) {
            return res.status(400).json({ error: 'Reminder title is required' });
        }

        if (!callAt) {
            return res.status(400).json({ error: 'Call time (callAt) is required' });
        }

        const callTime = new Date(callAt);
        if (isNaN(callTime.getTime())) {
            return res.status(400).json({ error: 'Invalid callAt date format. Use ISO 8601.' });
        }

        // Check if call is too far in the past (more than 5 minutes ago)
        if (callTime.getTime() < Date.now() - 5 * 60 * 1000) {
            return res.status(400).json({ error: 'Cannot schedule calls in the past.' });
        }

        // Format the due time for speech
        const dueTime = callTime.toLocaleTimeString('en-US', {
            hour: 'numeric',
            minute: '2-digit',
            hour12: true
        });

        const id = reminderId || `call_${Date.now()}`;

        // Check if this reminder already exists (update instead of duplicate)
        if (scheduledCalls.has(id)) {
            const existing = scheduledCalls.get(id);
            // Only update if not already called
            if (!existing.called) {
                existing.callAt = callTime.getTime();
                existing.reminderTitle = reminderTitle;
                existing.reminderDescription = reminderDescription || '';
                existing.dueTime = dueTime;
                console.log(`📝 Updated scheduled call: "${reminderTitle}" to ${to}`);

                const msUntilCall = callTime.getTime() - Date.now();
                return res.json({
                    success: true,
                    id,
                    message: `Call updated for ${dueTime}`,
                    minutesUntilCall: Math.max(0, Math.round(msUntilCall / 60000)),
                    updated: true
                });
            }
        }

        const scheduled = {
            id,
            to,
            reminderTitle,
            reminderDescription: reminderDescription || '',
            dueTime,
            callAt: callTime.getTime(),
            scheduledAt: new Date().toISOString(),
            called: false,
            status: 'scheduled'
        };

        scheduledCalls.set(id, scheduled);

        const msUntilCall = callTime.getTime() - Date.now();
        const minutesUntilCall = Math.round(msUntilCall / 60000);

        console.log(`📞 Scheduled call: "${reminderTitle}" to ${to} in ${minutesUntilCall} minutes`);

        // Run cleanup if needed
        enforceMaxSize();

        res.json({
            success: true,
            id,
            message: `Call scheduled for ${dueTime}`,
            minutesUntilCall: minutesUntilCall > 0 ? minutesUntilCall : 0
        });

    } catch (error) {
        console.error('Error scheduling call:', error);
        res.status(500).json({
            error: 'Failed to schedule call',
            message: error.message
        });
    }
});

// Cancel a scheduled call
app.delete('/schedule/:id', (req, res) => {
    const { id } = req.params;

    if (scheduledCalls.has(id)) {
        const scheduled = scheduledCalls.get(id);
        scheduledCalls.delete(id);
        console.log(`🗑️ Cancelled scheduled call: ${id} (${scheduled.reminderTitle})`);
        res.json({ success: true, message: 'Call cancelled' });
    } else {
        // Not an error - maybe already called or cleaned up
        res.json({ success: true, message: 'Call not found or already processed' });
    }
});

// Get all scheduled calls (for debugging)
app.get('/schedule', (req, res) => {
    const calls = Array.from(scheduledCalls.values()).map(c => ({
        id: c.id,
        reminderTitle: c.reminderTitle,
        to: c.to,
        callAt: new Date(c.callAt).toISOString(),
        status: c.status,
        called: c.called
    }));

    res.json({
        scheduledCalls: calls,
        count: calls.length
    });
});

// Initiate outbound call immediately
app.post('/call', async (req, res) => {
    try {
        const { to, reminderTitle, reminderDescription, dueTime } = req.body;

        if (!to) {
            return res.status(400).json({ error: 'Phone number (to) is required' });
        }

        if (!reminderTitle) {
            return res.status(400).json({ error: 'Reminder title is required' });
        }

        // Create the call with inline TwiML
        const call = await client.calls.create({
            to: to,
            from: twilioNumber,
            twiml: generateTwiML(reminderTitle, reminderDescription, dueTime),
            statusCallback: `${baseUrl}/status`,
            statusCallbackEvent: ['initiated', 'ringing', 'answered', 'completed'],
            statusCallbackMethod: 'POST'
        });

        // Store call info
        activeCalls.set(call.sid, {
            to,
            reminderTitle,
            status: call.status,
            createdAt: new Date().toISOString()
        });

        console.log(`📞 Call initiated: ${call.sid} to ${to}`);
        res.json({
            callSid: call.sid,
            status: call.status,
            message: 'Call initiated successfully'
        });

    } catch (error) {
        console.error('Error initiating call:', error);
        res.status(500).json({
            error: 'Failed to initiate call',
            message: error.message
        });
    }
});

// Handle gather (keypress) responses
app.post('/gather', (req, res) => {
    const digits = req.body.Digits;
    const callSid = req.body.CallSid;

    res.type('text/xml');

    if (digits === '1') {
        // Confirmation
        console.log(`✅ Call ${callSid}: Reminder acknowledged`);

        // Mark the scheduled call as completed (for cleanup)
        const callInfo = activeCalls.get(callSid);
        if (callInfo && callInfo.scheduledId) {
            const scheduled = scheduledCalls.get(callInfo.scheduledId);
            if (scheduled) {
                scheduled.status = 'acknowledged';
                scheduled.acknowledgedAt = new Date().toISOString();
            }
        }

        res.send(`
            <Response>
                <Say voice="Polly.Joanna">
                    Thank you! Your reminder has been acknowledged. Have a great day!
                </Say>
                <Hangup/>
            </Response>
        `);
    } else if (digits === '2') {
        // Snooze - schedule another call in 5 minutes
        console.log(`⏰ Call ${callSid}: Reminder snoozed for 5 minutes`);

        // Find the original call info and reschedule
        const callInfo = activeCalls.get(callSid);
        if (callInfo && callInfo.scheduledId) {
            const original = scheduledCalls.get(callInfo.scheduledId);
            if (original) {
                // Mark original as snoozed
                original.status = 'snoozed';
                original.snoozedAt = new Date().toISOString();

                // Schedule new call in 5 minutes
                const newId = `snooze_${Date.now()}`;
                const newCallTime = Date.now() + (5 * 60 * 1000);

                scheduledCalls.set(newId, {
                    ...original,
                    id: newId,
                    callAt: newCallTime,
                    called: false,
                    status: 'scheduled',
                    scheduledAt: new Date().toISOString(),
                    snoozedFrom: callInfo.scheduledId
                });

                console.log(`📅 Rescheduled call for 5 minutes: ${newId}`);
            }
        }

        res.send(`
            <Response>
                <Say voice="Polly.Joanna">
                    Got it! I will call you again in 5 minutes.
                </Say>
                <Hangup/>
            </Response>
        `);
    } else {
        res.send(`
            <Response>
                <Say voice="Polly.Joanna">
                    Sorry, I didn't understand that. Press 1 to confirm, or 2 to snooze.
                </Say>
                <Gather numDigits="1" action="${baseUrl}/gather" method="POST" timeout="10"/>
            </Response>
        `);
    }
});

// Status callback from Twilio
app.post('/status', (req, res) => {
    const { CallSid, CallStatus } = req.body;

    if (activeCalls.has(CallSid)) {
        const callInfo = activeCalls.get(CallSid);
        callInfo.status = CallStatus;
        callInfo.updatedAt = new Date().toISOString();

        console.log(`📊 Call ${CallSid} status: ${CallStatus}`);

        // Update the scheduled call status too
        if (callInfo.scheduledId && scheduledCalls.has(callInfo.scheduledId)) {
            const scheduled = scheduledCalls.get(callInfo.scheduledId);
            if (CallStatus === 'completed' && scheduled.status !== 'acknowledged') {
                scheduled.status = 'completed';
            } else if (['failed', 'busy', 'no-answer', 'canceled'].includes(CallStatus)) {
                scheduled.status = CallStatus;
            }
        }

        // Remove from activeCalls after terminal states (with delay for final updates)
        if (['completed', 'failed', 'busy', 'no-answer', 'canceled'].includes(CallStatus)) {
            setTimeout(() => activeCalls.delete(CallSid), 60000);  // 1 minute delay
        }
    }

    res.sendStatus(200);
});

// Get call status
app.get('/call/status/:callSid', (req, res) => {
    const { callSid } = req.params;

    if (activeCalls.has(callSid)) {
        res.json(activeCalls.get(callSid));
    } else {
        res.status(404).json({ error: 'Call not found' });
    }
});

// Debug endpoint - get memory stats
app.get('/debug/stats', (req, res) => {
    const memUsage = process.memoryUsage();
    res.json({
        memory: {
            heapUsed: Math.round(memUsage.heapUsed / 1024 / 1024) + 'MB',
            heapTotal: Math.round(memUsage.heapTotal / 1024 / 1024) + 'MB',
            rss: Math.round(memUsage.rss / 1024 / 1024) + 'MB'
        },
        scheduledCalls: scheduledCalls.size,
        activeCalls: activeCalls.size,
        uptime: Math.floor(process.uptime()) + 's'
    });
});

// Serve static audio files
app.use('/audio', express.static('audio'));

// Helper function to escape XML special characters
function escapeXml(text) {
    if (!text) return '';
    return text
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&apos;');
}

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('🛑 SIGTERM received. Shutting down gracefully...');
    clearInterval(schedulerInterval);
    process.exit(0);
});

process.on('SIGINT', () => {
    console.log('🛑 SIGINT received. Shutting down gracefully...');
    clearInterval(schedulerInterval);
    process.exit(0);
});

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`🚀 NoForget Twilio backend running on port ${PORT}`);
    console.log(`📞 Twilio number: ${twilioNumber}`);
    console.log(`🌐 Base URL: ${baseUrl}`);
    console.log(`📅 Scheduler active - checking for due calls every 30 seconds`);
    console.log(`🧹 Cleanup runs every 5 minutes`);
});
