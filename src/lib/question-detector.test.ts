import { describe, it, expect } from 'vitest';
import { isQuestion, isSubstantialQuestion } from './question-detector';

describe('isQuestion', () => {
  it('detects questions ending with ?', () => {
    expect(isQuestion('What is your experience with scaling teams?')).toBe(true);
    expect(isQuestion('Can you walk me through that?')).toBe(true);
  });

  it('detects questions starting with question words', () => {
    expect(isQuestion('How would you approach this problem')).toBe(true);
    expect(isQuestion('Tell me about a time you failed')).toBe(true);
    expect(isQuestion('Describe your leadership style')).toBe(true);
    expect(isQuestion('Walk me through your last project')).toBe(true);
  });

  it('rejects non-questions', () => {
    expect(isQuestion('That sounds great')).toBe(false);
    expect(isQuestion('I agree with that approach')).toBe(false);
    expect(isQuestion('Let me share some context')).toBe(false);
  });
});

describe('isSubstantialQuestion', () => {
  it('filters out short questions', () => {
    expect(isSubstantialQuestion('Right?')).toBe(false);
    expect(isSubstantialQuestion('OK?')).toBe(false);
    expect(isSubstantialQuestion('You know?')).toBe(false);
  });

  it('keeps substantial questions', () => {
    expect(
      isSubstantialQuestion('Tell me about a time you scaled a product team')
    ).toBe(true);
    expect(
      isSubstantialQuestion('How would you handle a disagreement with engineering?')
    ).toBe(true);
  });
});
