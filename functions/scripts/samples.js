const word = (text, x, y, size = 104, rotation = 0) => ({text, x, y, size, rotation});
export const samples = [
  {
    answer: 'head over heels', difficulty: 'easy', mechanic: 'position',
    hints: ['Think of a phrase about being completely in love.', 'Look at where the two words sit relative to one another.', 'Read the upper word, a position word, and then the lower word.'],
    explanation: 'HEAD is placed above HEELS. Reading that arrangement as HEAD over HEELS gives the phrase describing being completely in love.',
    words: [word('HEAD', 540, 425, 130), word('HEELS', 540, 650, 130)], shapes: [],
  },
  {
    answer: 'reading between the lines', difficulty: 'easy', mechanic: 'position',
    hints: ['The phrase involves understanding an unstated meaning.', 'The horizontal marks matter as much as the word.', 'Describe where the activity appears relative to both marks.'],
    explanation: 'The word READING is placed between two horizontal lines. Together they represent reading between the lines: noticing an implied meaning.',
    words: [word('READING', 540, 550, 112)],
    shapes: [{type: 'line', x: 180, y: 410, width: 720, height: 0}, {type: 'line', x: 180, y: 690, width: 720, height: 0}],
  },
  {
    answer: 'split decision', difficulty: 'medium', mechanic: 'spacing',
    hints: ['This can describe a result when judges do not agree.', 'The letters would normally make one word.', 'Notice the large gap dividing that word into two pieces.'],
    explanation: 'DECISION is separated into DECI and SION with a large gap. The word decision has been split, representing a split decision.',
    words: [word('DECI', 275, 550, 108), word('SION', 805, 550, 108)], shapes: [],
  },
  {
    answer: 'one in a million', difficulty: 'medium', mechanic: 'containment',
    hints: ['This phrase describes someone extremely rare or special.', 'A digit has been inserted into a familiar large number word.', 'Identify the digit and the word surrounding it.'],
    explanation: 'The numeral 1 is inserted inside the letters of MILLION. This shows one in a million, a phrase for someone or something exceptionally rare.',
    words: [word('MIL1LION', 540, 550, 124)], shapes: [],
  },
  {
    answer: 'life after death', difficulty: 'easy', mechanic: 'position',
    hints: ['Think of a phrase about what might follow our time in this world.', 'Read the two words from left to right.', 'The second word comes after the first.'],
    explanation: 'When read from left to right, LIFE comes after DEATH. Their order represents the phrase life after death.',
    words: [word('DEATH', 315, 550, 102), word('LIFE', 800, 550, 102)], shapes: [],
  },
  {
    answer: 'back door', difficulty: 'easy', mechanic: 'reversal',
    hints: ['This refers to an entrance to a building.', 'The visible letters spell a familiar object in reverse.', 'Read the letters from right to left, then describe their direction.'],
    explanation: 'DOOR is written backwards as ROOD. A backwards door represents the phrase back door.',
    words: [word('ROOD', 540, 550, 170)], shapes: [],
  },
];
