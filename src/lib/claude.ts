import type { ContextDoc, MeetingMode, MockQA } from '../types';

const MODE_PROMPTS: Record<MeetingMode, string> = {
  interview: `You are an interview coach providing real-time suggestions. When the interviewer asks a question:
- Suggest a structured response using the STAR framework (Situation, Task, Action, Result) when appropriate
- Reference the loaded context documents for company-specific details
- Keep suggestions concise (3-5 bullet points max)
- Focus on concrete examples and measurable outcomes
- If a framework is loaded, structure the response using that framework`,

  'parent-teacher': `You are helping a parent during a parent-teacher conference. When the teacher speaks:
- Suggest clarifying questions to ask
- Note important follow-up items
- Flag any concerns that need discussion
- Keep suggestions brief and actionable`,

  financial: `You are assisting during a financial advisory meeting. When the advisor speaks:
- Explain any jargon or complex terms simply
- Suggest clarifying questions about fees, risks, or alternatives
- Flag important decisions or commitments being discussed
- Note action items`,

  general: `You are a meeting assistant. When someone asks a question or raises a topic:
- Suggest relevant talking points
- Note action items as they come up
- Summarize key decisions
- Keep suggestions brief`,

  'mock-interview': `You are a hiring manager conducting a practice interview. Your role:
- Ask one question at a time
- After the candidate responds, give brief, specific feedback (strengths and areas to improve)
- Then ask the next question
- Mix behavioral ("Tell me about a time...") and situational questions
- Use the STAR framework to evaluate responses
- Be encouraging but honest — point out vague answers or missing specifics
- Reference context documents for role-specific questions`,
};

async function streamResponse(
  apiKey: string,
  system: string,
  messages: { role: 'user' | 'assistant'; content: string }[],
  onChunk: (text: string) => void,
  maxTokens = 500
): Promise<string> {
  const response = await fetch('https://api.anthropic.com/v1/messages', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'x-api-key': apiKey,
      'anthropic-version': '2023-06-01',
      'anthropic-dangerous-direct-browser-access': 'true',
    },
    body: JSON.stringify({
      model: 'claude-sonnet-4-20250514',
      max_tokens: maxTokens,
      stream: true,
      system,
      messages,
    }),
  });

  if (!response.ok) {
    throw new Error(`Claude API error: ${response.status}`);
  }

  const reader = response.body!.getReader();
  const decoder = new TextDecoder();
  let fullText = '';

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    const chunk = decoder.decode(value, { stream: true });
    const lines = chunk.split('\n');

    for (const line of lines) {
      if (line.startsWith('data: ')) {
        try {
          const data = JSON.parse(line.slice(6));
          if (
            data.type === 'content_block_delta' &&
            data.delta?.type === 'text_delta'
          ) {
            fullText += data.delta.text;
            onChunk(fullText);
          }
        } catch {
          // skip non-JSON lines
        }
      }
    }
  }

  return fullText;
}

export async function generateSuggestion(
  apiKey: string,
  mode: MeetingMode,
  contextDocs: ContextDoc[],
  frameworks: string[],
  recentTranscript: string,
  currentQuestion: string,
  onChunk: (text: string) => void
): Promise<string> {
  const contextBlock = contextDocs
    .map((d) => `### ${d.title}\n${d.content}`)
    .join('\n\n');

  const frameworkBlock =
    frameworks.length > 0
      ? `\nActive frameworks: ${frameworks.join(', ')}`
      : '';

  const systemPrompt = `${MODE_PROMPTS[mode]}${frameworkBlock}

${contextBlock ? `## Context Documents\n${contextBlock}` : ''}

Respond with a concise, actionable suggestion. Use markdown formatting sparingly. Focus on what the user should say or do next.`;

  return streamResponse(
    apiKey,
    systemPrompt,
    [
      {
        role: 'user',
        content: `Recent conversation:\n${recentTranscript}\n\nCurrent question/topic to respond to:\n"${currentQuestion}"\n\nProvide a suggested response.`,
      },
    ],
    onChunk
  );
}

export async function generateInterviewQuestion(
  apiKey: string,
  contextDocs: ContextDoc[],
  history: MockQA[],
  latestAnswer: string | null,
  onChunk: (text: string) => void
): Promise<string> {
  const contextBlock = contextDocs
    .map((d) => `### ${d.title}\n${d.content}`)
    .join('\n\n');

  const systemPrompt = `${MODE_PROMPTS['mock-interview']}

${contextBlock ? `## Context Documents (Role/Company Info)\n${contextBlock}` : ''}

Format your response as:
1. If this is NOT the first question and the candidate just answered, start with **Feedback:** followed by 2-3 sentences of specific feedback on their answer.
2. Then **Question:** followed by your next interview question.

Keep feedback constructive and specific. Reference what was good and what could be stronger.`;

  // Build conversation messages from history
  const messages: { role: 'user' | 'assistant'; content: string }[] = [];

  if (history.length === 0 && !latestAnswer) {
    // First question — no history
    messages.push({
      role: 'user',
      content: 'Start the mock interview. Ask your first question.',
    });
  } else {
    // Replay history as conversation
    messages.push({
      role: 'user',
      content: 'Start the mock interview. Ask your first question.',
    });

    for (const qa of history) {
      // Interviewer's question
      messages.push({ role: 'assistant', content: qa.question });
      // Candidate's answer
      messages.push({ role: 'user', content: qa.answer });
    }

    if (latestAnswer) {
      // If there's a new answer not yet in history
      if (history.length > 0) {
        // The last assistant message was the question, user just answered
      } else {
        messages.push({ role: 'assistant', content: 'Let me ask you a question.' });
      }
      messages.push({ role: 'user', content: latestAnswer });
    }
  }

  return streamResponse(apiKey, systemPrompt, messages, onChunk, 600);
}
