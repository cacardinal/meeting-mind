const QUESTION_STARTERS = [
  'how',
  'what',
  'why',
  'when',
  'where',
  'who',
  'which',
  'tell me',
  'describe',
  'explain',
  'can you',
  'could you',
  'would you',
  'walk me through',
  'give me an example',
  'have you',
  'do you',
  'did you',
  'are you',
  'were you',
  'is there',
  'what about',
  'how would you',
  'how do you',
  'what is your',
  'what are your',
];

export function isQuestion(text: string): boolean {
  const lower = text.toLowerCase().trim();

  // Ends with question mark
  if (lower.endsWith('?')) return true;

  // Starts with question word/phrase
  for (const starter of QUESTION_STARTERS) {
    if (lower.startsWith(starter)) return true;
  }

  return false;
}

export function isSubstantialQuestion(text: string): boolean {
  // Filter out very short questions like "right?" "ok?"
  if (text.split(/\s+/).length < 4) return false;
  return isQuestion(text);
}
