import re
import json
import os

# Read the questions database
with open('lib/data/questions_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Extract question blocks
def extract_questions(text):
    questions = []
    q_pattern = r"Question\(\s*id:\s*\'([^\']+?)\'\s*,\s*subject:\s*\'([^\']+?)\'\s*,\s*topic:\s*\'([^\']+?)\'\s*,\s*questionText:\s*\'([^\']+?)\'\s*,\s*options:\s*\[([^\]]*?)\]\s*,\s*correctAnswerIndex:\s*(\d+)\s*,\s*difficulty:\s*Difficulty\.(\w+)\s*,\s*explanation:\s*\'([^\']+?)\'"
    matches = re.findall(q_pattern, text)
    for m in matches:
        opts = [o.strip().strip("'\" ") for o in m[4].split(',') if o.strip()]
        questions.append({
            'id': m[0],
            'subject': m[1],
            'topic': m[2],
            'question': m[3],
            'options': opts,
            'correct': int(m[5]),
            'difficulty': m[6],
            'explanation': m[7]
        })
    return questions

questions = extract_questions(content)
print(f'Total questions extracted: {len(questions)}')

# Group by subject and topic
subjects = {}
for q in questions:
    sid = q['subject']
    topic = q['topic']
    if sid not in subjects:
        subjects[sid] = {}
    if topic not in subjects[sid]:
        subjects[sid][topic] = []
    subjects[sid][topic].append(q)

for sid, topics in subjects.items():
    total = sum(len(v) for v in topics.values())
    print(f'{sid}: {len(topics)} topics, {total} questions')

# Create modules directory
os.makedirs('assets/modules', exist_ok=True)

# Generate module JSON for each subject
subject_names = {
    'criminal_jurisprudence': 'Criminal Jurisprudence',
    'law_enforcement': 'Law Enforcement Administration',
    'criminalistics': 'Criminalistics',
    'crime_detection': 'Crime Detection and Investigation',
    'criminology': 'Criminology',
    'corrections': 'Correctional Administration',
}

subject_descriptions = {
    'criminal_jurisprudence': 'Study of criminal law, procedure, evidence, and court testimony for the Philippine criminology board examination.',
    'law_enforcement': 'Police organization, operations, intelligence, and administration principles.',
    'criminalistics': 'Forensic science including identification, ballistics, documents, and DNA analysis.',
    'crime_detection': 'Methods and techniques for criminal investigation and crime scene processing.',
    'criminology': 'Theories of crime causation, human behavior, ethics, and juvenile justice.',
    'corrections': 'Institutional and non-institutional correctional administration and rehabilitation.',
}

for sid, topics in subjects.items():
    module_data = {
        'id': sid,
        'title': subject_names.get(sid, sid),
        'description': subject_descriptions.get(sid, ''),
        'totalItems': sum(len(v) for v in topics.values()),
        'chapters': []
    }

    for topic_idx, (topic, qs) in enumerate(topics.items()):
        # Extract key concepts from explanations (max 8)
        concepts = []
        for q in qs:
            expl = q['explanation']
            sentences = [s.strip() for s in expl.split('.') if len(s.strip()) > 10]
            for s in sentences:
                if s not in concepts and len(concepts) < 8:
                    concepts.append(s)

        chapter = {
            'number': topic_idx + 1,
            'title': topic,
            'itemCount': len(qs),
            'introduction': f'This chapter covers {topic} with {len(qs)} review items essential for the board examination.',
            'keyConcepts': concepts,
            'content': f'## {topic}\n\nStudy the following concepts and review items related to {topic}. Understanding these concepts is essential for passing the criminology board examination.\n\n### Important Points to Remember:\n\n' + '\n'.join([f'- {c}' for c in concepts]) + f'\n\n### Review Items ({len(qs)} total):\n'
        }
        module_data['chapters'].append(chapter)

    # Save as JSON
    filename = f'assets/modules/{sid}_module.json'
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(module_data, f, indent=2, ensure_ascii=False)
    print(f'Generated: {filename}')

print('\nAll module files generated!')
