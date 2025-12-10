require('dotenv').config();
const express = require('express');
const twilio = require('twilio');

const app = express();
app.use(express.json());

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

// Store active calls for status tracking
const activeCalls = new Map();

// Health check endpoint
app.get('/health', (req, res) => {
    res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Initiate outbound call for reminder
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
            twiml: `
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
                        <Play loop="3">${baseUrl}/audio/alert.mp3</Play>
                    </Gather>
                    <Say voice="Polly.Joanna" language="en-US">
                        No response received. This reminder will repeat in 5 minutes if not acknowledged.
                    </Say>
                </Response>
            `,
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

        console.log(`Call initiated: ${call.sid} to ${to}`);
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
        console.log(`Call ${callSid}: Reminder acknowledged`);
        res.send(`
            <Response>
                <Say voice="Polly.Joanna">
                    Thank you! Your reminder has been acknowledged. Have a great day!
                </Say>
                <Hangup/>
            </Response>
        `);
    } else if (digits === '2') {
        // Snooze - would trigger a new call in 5 minutes
        console.log(`Call ${callSid}: Reminder snoozed for 5 minutes`);
        res.send(`
            <Response>
                <Say voice="Polly.Joanna">
                    Got it! I will call you again in 5 minutes.
                </Say>
                <Hangup/>
            </Response>
        `);
        // In production, you'd schedule another call here
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

        console.log(`Call ${CallSid} status: ${CallStatus}`);

        // Clean up completed calls after 1 hour
        if (['completed', 'failed', 'busy', 'no-answer', 'canceled'].includes(CallStatus)) {
            setTimeout(() => activeCalls.delete(CallSid), 3600000);
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

// Start server
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
    console.log(`NoForget Twilio backend running on port ${PORT}`);
    console.log(`Twilio number: ${twilioNumber}`);
});
