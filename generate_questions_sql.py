import re
import json

def unescape_dart(s):
    """Unescape Dart string escapes"""
    if s is None:
        return None
    # Dart uses \' for single quotes inside single-quoted strings
    return s.replace("\\'", "'").replace("\\n", "\n")

def escape_sql(s):
    """Escape single quotes for SQL"""
    if s is None:
        return 'NULL'
    # First unescape Dart, then double single quotes for SQL
    s = unescape_dart(s)
    return s.replace("'", "''")

def escape_json_for_sql(options):
    """Create JSON array that's safe for SQL insertion"""
    import json
    # Unescape Dart strings first
    clean_options = [unescape_dart(opt) for opt in options]
    # Create proper JSON
    json_str = json.dumps(clean_options)
    # Escape single quotes for SQL
    return json_str.replace("'", "''")

def parse_questions(dart_file):
    """Parse questions from Dart file"""
    with open(dart_file, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # Find all Question blocks
    pattern = r"Question\(\s*id:\s*'([^']+)',\s*subject:\s*'([^']+)',\s*topic:\s*'([^']+)',\s*questionText:\s*'([^']+)',\s*options:\s*\[([^\]]+)\],\s*correctAnswerIndex:\s*(\d+),\s*difficulty:\s*Difficulty\.(\w+),\s*explanation:\s*'([^']*)',"
    
    questions = []
    
    # Use a more flexible approach - find each Question( block
    q_starts = [m.start() for m in re.finditer(r'Question\(', content)]
    
    for start in q_starts:
        # Find the matching closing paren
        depth = 0
        end = start
        for i, c in enumerate(content[start:], start):
            if c == '(':
                depth += 1
            elif c == ')':
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        
        block = content[start:end]
        
        # Extract fields
        id_match = re.search(r"id:\s*'([^']+)'", block)
        subject_match = re.search(r"subject:\s*'([^']+)'", block)
        topic_match = re.search(r"topic:\s*'([^']+)'", block)
        
        # Question text might span multiple lines or use different quote styles
        qtext_match = re.search(r"questionText:\s*'((?:[^'\\]|\\.)*)'", block)
        if not qtext_match:
            qtext_match = re.search(r'questionText:\s*"((?:[^"\\]|\\.)*)"', block)
        
        # Options array
        options_match = re.search(r"options:\s*\[(.*?)\]", block, re.DOTALL)
        
        correct_match = re.search(r"correctAnswerIndex:\s*(\d+)", block)
        diff_match = re.search(r"difficulty:\s*Difficulty\.(\w+)", block)
        
        # Explanation might be missing or use different quote styles
        expl_match = re.search(r"explanation:\s*'((?:[^'\\]|\\.)*)'", block)
        if not expl_match:
            expl_match = re.search(r'explanation:\s*"((?:[^"\\]|\\.)*)"', block)
        
        if all([id_match, subject_match, topic_match, qtext_match, options_match, correct_match, diff_match]):
            # Parse options
            options_str = options_match.group(1)
            options = re.findall(r"'((?:[^'\\]|\\.)*)'", options_str)
            if not options:
                options = re.findall(r'"((?:[^"\\]|\\.)*)"', options_str)
            
            q = {
                'id': id_match.group(1),
                'subject': subject_match.group(1),
                'topic': topic_match.group(1),
                'question_text': qtext_match.group(1),
                'options': options,
                'correct_answer_index': int(correct_match.group(1)),
                'difficulty': diff_match.group(1).lower(),
                'explanation': expl_match.group(1) if expl_match else None
            }
            questions.append(q)
    
    return questions

def generate_sql(questions):
    """Generate SQL INSERT statements"""
    sql_lines = [
        "-- Auto-generated questions insert statements",
        "-- Run this in Supabase SQL Editor after creating the questions table",
        "",
        "INSERT INTO questions (id, subject, topic, question_text, options, correct_answer_index, difficulty, explanation) VALUES"
    ]
    
    values = []
    for q in questions:
        options_json = escape_json_for_sql(q['options'])
        expl = f"'{escape_sql(q['explanation'])}'" if q['explanation'] else 'NULL'
        
        val = f"('{escape_sql(q['id'])}', '{escape_sql(q['subject'])}', '{escape_sql(q['topic'])}', '{escape_sql(q['question_text'])}', '{options_json}'::jsonb, {q['correct_answer_index']}, '{q['difficulty']}', {expl})"
        values.append(val)
    
    # Split into batches of 100 for easier execution
    batch_size = 100
    batches = [values[i:i+batch_size] for i in range(0, len(values), batch_size)]
    
    all_sql = []
    for i, batch in enumerate(batches):
        batch_sql = "INSERT INTO questions (id, subject, topic, question_text, options, correct_answer_index, difficulty, explanation) VALUES\n"
        batch_sql += ",\n".join(batch)
        batch_sql += "\nON CONFLICT (id) DO UPDATE SET\n"
        batch_sql += "  subject = EXCLUDED.subject,\n"
        batch_sql += "  topic = EXCLUDED.topic,\n"
        batch_sql += "  question_text = EXCLUDED.question_text,\n"
        batch_sql += "  options = EXCLUDED.options,\n"
        batch_sql += "  correct_answer_index = EXCLUDED.correct_answer_index,\n"
        batch_sql += "  difficulty = EXCLUDED.difficulty,\n"
        batch_sql += "  explanation = EXCLUDED.explanation,\n"
        batch_sql += "  updated_at = NOW();\n"
        all_sql.append(f"-- Batch {i+1} of {len(batches)}\n{batch_sql}")
    
    return "\n".join(all_sql)

if __name__ == '__main__':
    dart_file = 'lib/data/questions_database.dart'
    print(f"Parsing questions from {dart_file}...")
    
    questions = parse_questions(dart_file)
    print(f"Found {len(questions)} questions")
    
    # Count by subject
    subjects = {}
    for q in questions:
        subjects[q['subject']] = subjects.get(q['subject'], 0) + 1
    
    print("\nQuestions by subject:")
    for s, c in sorted(subjects.items()):
        print(f"  {s}: {c}")
    
    # Generate SQL
    sql = generate_sql(questions)
    
    output_file = 'supabase/questions_data.sql'
    with open(output_file, 'w', encoding='utf-8') as f:
        f.write(sql)
    
    print(f"\nSQL written to {output_file}")
    print(f"Total statements: {len(questions)} questions in batches of 100")
