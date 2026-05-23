import '../models/question.dart';

class QuestionBank {
  static final List<Question> _allQuestions = [
    // ==================== CRIMINAL LAW ====================
    // Revised Penal Code Book 1
    Question(
      id: 'cl_001',
      subject: 'criminal_law',
      topic: 'Revised Penal Code Book 1',
      questionText: 'What is the basis of criminal liability under the Revised Penal Code?',
      options: [
        'Dolo and Culpa',
        'Intent and Motive',
        'Negligence only',
        'Strict liability'
      ],
      correctAnswerIndex: 0,
      explanation: 'Criminal liability is based on dolo (deceit/malice) and culpa (fault/negligence) under Article 3 of the RPC.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'cl_002',
      subject: 'criminal_law',
      topic: 'Revised Penal Code Book 1',
      questionText: 'Under Article 11 of the RPC, which of the following is a justifying circumstance?',
      options: [
        'Minority',
        'Self-defense',
        'Passion and obfuscation',
        'Voluntary surrender'
      ],
      correctAnswerIndex: 1,
      explanation: 'Self-defense is a justifying circumstance under Article 11, which exempts a person from criminal and civil liability.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'cl_003',
      subject: 'criminal_law',
      topic: 'Justifying Circumstances',
      questionText: 'What are the three elements of self-defense?',
      options: [
        'Unlawful aggression, reasonable necessity, lack of sufficient provocation',
        'Intent, motive, opportunity',
        'Premeditation, treachery, evident premeditation',
        'Minority, insanity, imbecility'
      ],
      correctAnswerIndex: 0,
      explanation: 'The three elements are: unlawful aggression, reasonable necessity of the means employed, and lack of sufficient provocation on the part of the person defending himself.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cl_004',
      subject: 'criminal_law',
      topic: 'Exempting Circumstances',
      questionText: 'Under Article 12 of the RPC, an imbecile or insane person is:',
      options: [
        'Exempt from criminal liability',
        'Subject to reduced penalty',
        'Fully liable',
        'Subject to aggravated penalty'
      ],
      correctAnswerIndex: 0,
      explanation: 'An imbecile or insane person is exempt from criminal liability unless he acted during a lucid interval.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'cl_005',
      subject: 'criminal_law',
      topic: 'Mitigating Circumstances',
      questionText: 'Which of the following is a mitigating circumstance under Article 13?',
      options: [
        'Treachery',
        'Voluntary surrender',
        'Recidivism',
        'Use of superior strength'
      ],
      correctAnswerIndex: 1,
      explanation: 'Voluntary surrender is a mitigating circumstance that reduces the penalty imposed on the offender.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'cl_006',
      subject: 'criminal_law',
      topic: 'Aggravating Circumstances',
      questionText: 'Treachery as an aggravating circumstance requires:',
      options: [
        'Employment of means to ensure commission without risk from defense',
        'Use of poison',
        'Commission during nighttime',
        'Presence of two or more armed persons'
      ],
      correctAnswerIndex: 0,
      explanation: 'Treachery (alevosia) involves employing means, methods, or forms that directly and specially ensure execution without risk to the offender from any defense the victim might make.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cl_007',
      subject: 'criminal_law',
      topic: 'Revised Penal Code Book 2',
      questionText: 'Murder is punishable under what article of the Revised Penal Code?',
      options: [
        'Article 246',
        'Article 248',
        'Article 249',
        'Article 255'
      ],
      correctAnswerIndex: 1,
      explanation: 'Murder is defined and punished under Article 248 of the Revised Penal Code.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cl_008',
      subject: 'criminal_law',
      topic: 'Revised Penal Code Book 2',
      questionText: 'What distinguishes murder from homicide?',
      options: [
        'The weapon used',
        'Presence of qualifying circumstances like treachery',
        'The number of victims',
        'The location of the crime'
      ],
      correctAnswerIndex: 1,
      explanation: 'Murder is homicide attended by qualifying circumstances such as treachery, evident premeditation, or cruelty.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cl_009',
      subject: 'criminal_law',
      topic: 'Criminal Liability',
      questionText: 'What is the age of absolute criminal irresponsibility in the Philippines?',
      options: [
        'Below 9 years old',
        'Below 12 years old',
        'Below 15 years old',
        'Below 18 years old'
      ],
      correctAnswerIndex: 2,
      explanation: 'Under RA 9344 (Juvenile Justice and Welfare Act), children below 15 years old are exempt from criminal liability.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'cl_010',
      subject: 'criminal_law',
      topic: 'Penalties and Punishment',
      questionText: 'Reclusion perpetua has a duration of:',
      options: [
        '12 years and 1 day to 20 years',
        '20 years and 1 day to 40 years',
        '17 years, 4 months and 1 day to 20 years',
        '6 years and 1 day to 12 years'
      ],
      correctAnswerIndex: 1,
      explanation: 'Reclusion perpetua is imprisonment for 20 years and 1 day to 40 years.',
      difficulty: Difficulty.hard,
    ),
    Question(
      id: 'cl_011',
      subject: 'criminal_law',
      topic: 'Special Penal Laws',
      questionText: 'RA 9165 is also known as:',
      options: [
        'Anti-Violence Against Women and Children Act',
        'Comprehensive Dangerous Drugs Act of 2002',
        'Anti-Money Laundering Act',
        'Cybercrime Prevention Act'
      ],
      correctAnswerIndex: 1,
      explanation: 'RA 9165 is the Comprehensive Dangerous Drugs Act of 2002.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'cl_012',
      subject: 'criminal_law',
      topic: 'Special Penal Laws',
      questionText: 'Under RA 9262, psychological violence includes:',
      options: [
        'Physical harm only',
        'Marital rape only',
        'Intimidation, harassment, and emotional abuse',
        'Property damage only'
      ],
      correctAnswerIndex: 2,
      explanation: 'RA 9262 (VAWC) includes psychological violence such as intimidation, harassment, stalking, and emotional abuse.',
      difficulty: Difficulty.medium,
    ),

    // ==================== CRIMINAL JURISPRUDENCE ====================
    Question(
      id: 'cj_001',
      subject: 'jurisprudence',
      topic: 'Constitutional Law',
      questionText: 'The right against unreasonable searches and seizures is found in what Article of the 1987 Constitution?',
      options: [
        'Article II',
        'Article III',
        'Article IV',
        'Article V'
      ],
      correctAnswerIndex: 1,
      explanation: 'Article III (Bill of Rights), Section 2 protects against unreasonable searches and seizures.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'cj_002',
      subject: 'jurisprudence',
      topic: 'Bill of Rights',
      questionText: 'The Miranda rights include all EXCEPT:',
      options: [
        'Right to remain silent',
        'Right to counsel',
        'Right to bail',
        'Warning that statements may be used against the person'
      ],
      correctAnswerIndex: 2,
      explanation: 'Miranda rights include the right to remain silent, right to counsel, and warning about use of statements. Right to bail is a separate constitutional right.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cj_003',
      subject: 'jurisprudence',
      topic: 'Due Process',
      questionText: 'What are the two aspects of due process?',
      options: [
        'Criminal and Civil',
        'Substantive and Procedural',
        'Legal and Equitable',
        'Public and Private'
      ],
      correctAnswerIndex: 1,
      explanation: 'Due process has two aspects: substantive (the law itself must be fair) and procedural (fair procedure in applying the law).',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cj_004',
      subject: 'jurisprudence',
      topic: 'Court Systems',
      questionText: 'Which court has exclusive original jurisdiction over criminal cases where the penalty is imprisonment exceeding 6 years?',
      options: [
        'Municipal Trial Court',
        'Metropolitan Trial Court',
        'Regional Trial Court',
        'Court of Appeals'
      ],
      correctAnswerIndex: 2,
      explanation: 'Regional Trial Courts have exclusive original jurisdiction over criminal cases where the penalty exceeds 6 years imprisonment.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cj_005',
      subject: 'jurisprudence',
      topic: 'Evidence Law',
      questionText: 'The fruit of the poisonous tree doctrine means:',
      options: [
        'Evidence obtained from plants is inadmissible',
        'Evidence derived from illegally obtained evidence is inadmissible',
        'Circumstantial evidence is always inadmissible',
        'Hearsay evidence is admissible'
      ],
      correctAnswerIndex: 1,
      explanation: 'The fruit of the poisonous tree doctrine excludes evidence obtained as a result of illegal searches or other constitutional violations.',
      difficulty: Difficulty.hard,
    ),
    Question(
      id: 'cj_006',
      subject: 'jurisprudence',
      topic: 'Rules of Court',
      questionText: 'A warrantless arrest is valid when:',
      options: [
        'The person is suspected of any crime',
        'The person is committing, has just committed, or is about to commit a crime in the presence of the arresting officer',
        'The arresting officer has a personal grudge',
        'The crime was committed last month'
      ],
      correctAnswerIndex: 1,
      explanation: 'Under Rule 113, Section 5, warrantless arrests are valid for in flagrante delicto, hot pursuit, and escaped prisoners.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cj_007',
      subject: 'jurisprudence',
      topic: 'Legal Ethics',
      questionText: 'The principle of attorney-client privilege:',
      options: [
        'Can be waived only by the attorney',
        'Can be waived by the client',
        'Cannot be waived under any circumstances',
        'Applies only to criminal cases'
      ],
      correctAnswerIndex: 1,
      explanation: 'Attorney-client privilege belongs to the client and can only be waived by the client.',
      difficulty: Difficulty.hard,
    ),
    Question(
      id: 'cj_008',
      subject: 'jurisprudence',
      topic: 'Landmark Cases',
      questionText: 'People v. Marti established that:',
      options: [
        'Evidence obtained by private individuals is admissible',
        'All warrantless searches are invalid',
        'Miranda rights are absolute',
        'Confessions are always inadmissible'
      ],
      correctAnswerIndex: 0,
      explanation: 'People v. Marti held that constitutional protection against unreasonable searches applies only to government action, not private individuals.',
      difficulty: Difficulty.hard,
    ),
    Question(
      id: 'cj_009',
      subject: 'jurisprudence',
      topic: 'Legal Philosophy',
      questionText: 'The positivist school of criminology believes that:',
      options: [
        'Criminals exercise free will',
        'Crime is caused by factors beyond individual control',
        'Punishment should be severe',
        'All crimes deserve death penalty'
      ],
      correctAnswerIndex: 1,
      explanation: 'Positivist criminology, founded by Lombroso, Ferri, and Garofalo, holds that criminal behavior is determined by biological, psychological, and social factors.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'cj_010',
      subject: 'jurisprudence',
      topic: 'Constitutional Law',
      questionText: 'The writ of habeas corpus may be suspended:',
      options: [
        'By the President during invasion or rebellion',
        'By Congress at any time',
        'By the Supreme Court',
        'It can never be suspended'
      ],
      correctAnswerIndex: 0,
      explanation: 'Under Article VII, Section 18, the President may suspend the writ of habeas corpus in cases of invasion or rebellion when public safety requires it.',
      difficulty: Difficulty.medium,
    ),

    // ==================== FORENSIC SCIENCE ====================
    Question(
      id: 'fs_001',
      subject: 'forensic_science',
      topic: 'Crime Scene Investigation',
      questionText: 'The first responder at a crime scene should:',
      options: [
        'Immediately collect evidence',
        'Secure and preserve the crime scene',
        'Interview witnesses before securing the scene',
        'Move the body for examination'
      ],
      correctAnswerIndex: 1,
      explanation: 'The first priority is to secure and preserve the crime scene to prevent contamination of evidence.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'fs_002',
      subject: 'forensic_science',
      topic: 'DNA Analysis',
      questionText: 'DNA profiling is most commonly performed using:',
      options: [
        'Blood type analysis',
        'Short Tandem Repeats (STR)',
        'Fingerprint comparison',
        'Hair color analysis'
      ],
      correctAnswerIndex: 1,
      explanation: 'STR analysis examines specific regions of DNA that vary between individuals, providing highly accurate identification.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'fs_003',
      subject: 'forensic_science',
      topic: 'Fingerprint Analysis',
      questionText: 'The three basic fingerprint patterns are:',
      options: [
        'Loop, Whorl, Arch',
        'Circle, Square, Triangle',
        'Ridge, Valley, Delta',
        'Radial, Ulnar, Central'
      ],
      correctAnswerIndex: 0,
      explanation: 'The three fundamental fingerprint patterns are loops (60-65%), whorls (30-35%), and arches (5%).',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'fs_004',
      subject: 'forensic_science',
      topic: 'Toxicology',
      questionText: 'Post-mortem redistribution affects:',
      options: [
        'Fingerprint quality',
        'Drug concentration in tissues',
        'DNA integrity',
        'Bullet trajectory'
      ],
      correctAnswerIndex: 1,
      explanation: 'Post-mortem redistribution causes drugs to move between tissues after death, affecting concentration measurements.',
      difficulty: Difficulty.hard,
    ),
    Question(
      id: 'fs_005',
      subject: 'forensic_science',
      topic: 'Ballistics',
      questionText: 'Rifling marks on a bullet are caused by:',
      options: [
        'The firing pin',
        'The spiral grooves inside the gun barrel',
        'The bullet casing',
        'Air resistance'
      ],
      correctAnswerIndex: 1,
      explanation: 'Rifling consists of spiral grooves in the barrel that spin the bullet for accuracy, leaving unique marks.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'fs_006',
      subject: 'forensic_science',
      topic: 'Forensic Chemistry',
      questionText: 'The Marquis reagent is used to test for:',
      options: [
        'Blood',
        'Drugs like heroin and amphetamines',
        'Gunshot residue',
        'DNA'
      ],
      correctAnswerIndex: 1,
      explanation: 'Marquis reagent is a presumptive test that produces color changes when exposed to certain drugs.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'fs_007',
      subject: 'forensic_science',
      topic: 'Document Examination',
      questionText: 'Indented writing can be revealed using:',
      options: [
        'DNA analysis',
        'ESDA (Electrostatic Detection Apparatus)',
        'Spectroscopy',
        'Luminol'
      ],
      correctAnswerIndex: 1,
      explanation: 'ESDA detects indented impressions on paper that may not be visible to the naked eye.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'fs_008',
      subject: 'forensic_science',
      topic: 'Digital Forensics',
      questionText: 'Chain of custody in digital forensics ensures:',
      options: [
        'Fast processing of evidence',
        'Evidence integrity and admissibility',
        'Cost-effective investigation',
        'Public access to evidence'
      ],
      correctAnswerIndex: 1,
      explanation: 'Chain of custody documents who handled the evidence and when, ensuring integrity and court admissibility.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'fs_009',
      subject: 'forensic_science',
      topic: 'Forensic Biology',
      questionText: 'Luminol is used to detect:',
      options: [
        'Fingerprints',
        'Latent bloodstains',
        'Drugs',
        'Explosives'
      ],
      correctAnswerIndex: 1,
      explanation: 'Luminol reacts with hemoglobin in blood, producing a blue glow that reveals cleaned or hidden bloodstains.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'fs_010',
      subject: 'forensic_science',
      topic: 'Crime Scene Investigation',
      questionText: 'The chain of custody refers to:',
      options: [
        'The sequence of arrests',
        'The documented trail of evidence handling',
        'The court proceedings',
        'The investigation timeline'
      ],
      correctAnswerIndex: 1,
      explanation: 'Chain of custody is the chronological documentation showing the seizure, custody, control, and disposition of evidence.',
      difficulty: Difficulty.easy,
    ),

    // ==================== LAW ENFORCEMENT ADMINISTRATION ====================
    Question(
      id: 'lea_001',
      subject: 'law_enforcement',
      topic: 'Police Organization',
      questionText: 'The Philippine National Police (PNP) is under what department?',
      options: [
        'Department of Justice',
        'Department of National Defense',
        'Department of the Interior and Local Government',
        'Office of the President'
      ],
      correctAnswerIndex: 2,
      explanation: 'Under RA 6975, the PNP is under the Department of the Interior and Local Government (DILG).',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'lea_002',
      subject: 'law_enforcement',
      topic: 'Police Operations',
      questionText: 'OPLAN is an abbreviation for:',
      options: [
        'Operational Planning',
        'Operations Plan',
        'Optional Planning',
        'Organized Plan'
      ],
      correctAnswerIndex: 1,
      explanation: 'OPLAN stands for Operations Plan, a directive for the conduct of police operations.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'lea_003',
      subject: 'law_enforcement',
      topic: 'Patrol Procedures',
      questionText: 'The primary purpose of police patrol is:',
      options: [
        'Revenue generation',
        'Crime prevention and public safety',
        'Political campaigns',
        'Entertainment'
      ],
      correctAnswerIndex: 1,
      explanation: 'Police patrol aims to prevent crime, maintain order, and provide services to the community.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'lea_004',
      subject: 'law_enforcement',
      topic: 'Traffic Management',
      questionText: 'RA 4136 is also known as:',
      options: [
        'Comprehensive Dangerous Drugs Act',
        'Land Transportation and Traffic Code',
        'Anti-Fencing Law',
        'Cybercrime Prevention Act'
      ],
      correctAnswerIndex: 1,
      explanation: 'RA 4136 is the Land Transportation and Traffic Code of the Philippines.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'lea_005',
      subject: 'law_enforcement',
      topic: 'Police Intelligence',
      questionText: 'HUMINT refers to:',
      options: [
        'Human Intelligence',
        'Humid Intelligence',
        'Humanitarian Intelligence',
        'Humble Intelligence'
      ],
      correctAnswerIndex: 0,
      explanation: 'HUMINT (Human Intelligence) is intelligence gathered through interpersonal contact.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'lea_006',
      subject: 'law_enforcement',
      topic: 'Community Relations',
      questionText: 'Community-Oriented Policing System (COPS) emphasizes:',
      options: [
        'Aggressive law enforcement',
        'Partnership between police and community',
        'Military-style operations',
        'Isolated police work'
      ],
      correctAnswerIndex: 1,
      explanation: 'COPS focuses on building trust and collaboration between law enforcement and the communities they serve.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'lea_007',
      subject: 'law_enforcement',
      topic: 'Human Rights',
      questionText: 'The Commission on Human Rights was created under what article of the Constitution?',
      options: [
        'Article XI',
        'Article XII',
        'Article XIII',
        'Article XIV'
      ],
      correctAnswerIndex: 2,
      explanation: 'Article XIII, Section 17 of the 1987 Constitution created the Commission on Human Rights.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'lea_008',
      subject: 'law_enforcement',
      topic: 'Police Planning',
      questionText: 'Strategic planning in law enforcement covers a period of:',
      options: [
        '1 year',
        '2-3 years',
        '5 years or more',
        '1 month'
      ],
      correctAnswerIndex: 2,
      explanation: 'Strategic planning is long-term planning that typically covers 5 years or more.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'lea_009',
      subject: 'law_enforcement',
      topic: 'Police Ethics',
      questionText: 'The PNP Code of Professional Conduct and Ethical Standards is found in:',
      options: [
        'NAPOLCOM MC 2016-002',
        'RA 6975',
        'RA 8551',
        'Executive Order 292'
      ],
      correctAnswerIndex: 0,
      explanation: 'NAPOLCOM Memorandum Circular 2016-002 contains the PNP Code of Professional Conduct and Ethical Standards.',
      difficulty: Difficulty.hard,
    ),
    Question(
      id: 'lea_010',
      subject: 'law_enforcement',
      topic: 'Police Organization',
      questionText: 'The PNP Reform and Reorganization Act is:',
      options: [
        'RA 6975',
        'RA 8551',
        'RA 9165',
        'RA 10591'
      ],
      correctAnswerIndex: 1,
      explanation: 'RA 8551 is the Philippine National Police Reform and Reorganization Act of 1998.',
      difficulty: Difficulty.medium,
    ),

    // ==================== CRIMINALISTICS ====================
    Question(
      id: 'crim_001',
      subject: 'criminalistics',
      topic: 'Personal Identification',
      questionText: 'The study of fingerprints for identification purposes is called:',
      options: [
        'Anthropometry',
        'Dactyloscopy',
        'Poroscopy',
        'Chiroscopy'
      ],
      correctAnswerIndex: 1,
      explanation: 'Dactyloscopy is the scientific study of fingerprints for identification purposes.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'crim_002',
      subject: 'criminalistics',
      topic: 'Dactyloscopy',
      questionText: 'Who is known as the Father of Fingerprint Identification?',
      options: [
        'Alphonse Bertillon',
        'Sir Francis Galton',
        'Juan Vucetich',
        'Sir Edward Henry'
      ],
      correctAnswerIndex: 2,
      explanation: 'Juan Vucetich of Argentina developed the first workable fingerprint classification system and is considered the Father of Fingerprint Identification.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'crim_003',
      subject: 'criminalistics',
      topic: 'Questioned Documents',
      questionText: 'A document whose origin or authenticity is in dispute is called:',
      options: [
        'Standard document',
        'Exemplar',
        'Questioned document',
        'Reference document'
      ],
      correctAnswerIndex: 2,
      explanation: 'A questioned document is any document whose authenticity, origin, or authorship is disputed.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'crim_004',
      subject: 'criminalistics',
      topic: 'Firearms Identification',
      questionText: 'The comparison microscope is primarily used in firearms examination to:',
      options: [
        'Measure bullet weight',
        'Compare striations on bullets',
        'Test gunpowder',
        'Measure muzzle velocity'
      ],
      correctAnswerIndex: 1,
      explanation: 'The comparison microscope allows simultaneous viewing of two bullets to compare their unique striation marks.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'crim_005',
      subject: 'criminalistics',
      topic: 'Photography',
      questionText: 'The overall photograph of a crime scene is called:',
      options: [
        'Close-up photograph',
        'General photograph',
        'Evidence photograph',
        'Identification photograph'
      ],
      correctAnswerIndex: 1,
      explanation: 'General or overview photographs show the entire crime scene and its relationship to surrounding areas.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'crim_006',
      subject: 'criminalistics',
      topic: 'Polygraphy',
      questionText: 'The polygraph measures all of the following EXCEPT:',
      options: [
        'Blood pressure',
        'Respiration',
        'Brain waves',
        'Galvanic skin response'
      ],
      correctAnswerIndex: 2,
      explanation: 'The polygraph measures cardiovascular activity, respiration, and galvanic skin response (GSR), not brain waves.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'crim_007',
      subject: 'criminalistics',
      topic: 'Modus Operandi',
      questionText: 'Modus operandi refers to:',
      options: [
        'The motive of the criminal',
        'The method or manner of committing a crime',
        'The criminal\'s background',
        'The victim\'s profile'
      ],
      correctAnswerIndex: 1,
      explanation: 'Modus operandi (M.O.) refers to the particular method or pattern used by a criminal in committing crimes.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'crim_008',
      subject: 'criminalistics',
      topic: 'Criminal Profiling',
      questionText: 'Criminal profiling is most useful in cases involving:',
      options: [
        'Property crimes',
        'Serial offenders',
        'Traffic violations',
        'Civil disputes'
      ],
      correctAnswerIndex: 1,
      explanation: 'Criminal profiling is most effective in cases involving serial crimes where behavioral patterns can be analyzed.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'crim_009',
      subject: 'criminalistics',
      topic: 'Surveillance Techniques',
      questionText: 'A fixed surveillance where the investigator remains stationary is called:',
      options: [
        'Shadowing',
        'Stakeout',
        'Tailing',
        'Undercover'
      ],
      correctAnswerIndex: 1,
      explanation: 'A stakeout is a fixed surveillance technique where officers observe a location from a stationary position.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'crim_010',
      subject: 'criminalistics',
      topic: 'Personal Identification',
      questionText: 'The Bertillon System of identification is based on:',
      options: [
        'Fingerprint patterns',
        'Body measurements',
        'DNA analysis',
        'Voice recognition'
      ],
      correctAnswerIndex: 1,
      explanation: 'Alphonse Bertillon developed anthropometry, a system of identification based on body measurements.',
      difficulty: Difficulty.medium,
    ),

    // ==================== CORRECTIONAL ADMINISTRATION ====================
    Question(
      id: 'ca_001',
      subject: 'corrections',
      topic: 'Prison Systems',
      questionText: 'The Bureau of Corrections (BuCor) is under what department?',
      options: [
        'Department of the Interior and Local Government',
        'Department of Justice',
        'Department of Social Welfare',
        'Department of National Defense'
      ],
      correctAnswerIndex: 1,
      explanation: 'The Bureau of Corrections is an agency under the Department of Justice.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'ca_002',
      subject: 'corrections',
      topic: 'Institutional Corrections',
      questionText: 'The national penitentiary for male offenders with sentences of more than 3 years is:',
      options: [
        'City Jail',
        'Provincial Jail',
        'New Bilibid Prison',
        'Municipal Jail'
      ],
      correctAnswerIndex: 2,
      explanation: 'New Bilibid Prison in Muntinlupa is the national penitentiary for male prisoners with sentences exceeding 3 years.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'ca_003',
      subject: 'corrections',
      topic: 'Non-Institutional Corrections',
      questionText: 'Which of the following is a form of non-institutional correction?',
      options: [
        'Imprisonment',
        'Probation',
        'Detention',
        'Incarceration'
      ],
      correctAnswerIndex: 1,
      explanation: 'Probation allows offenders to serve their sentence in the community under supervision instead of prison.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'ca_004',
      subject: 'corrections',
      topic: 'Probation',
      questionText: 'The Probation Law of the Philippines is:',
      options: [
        'PD 968',
        'RA 6975',
        'RA 9165',
        'RA 10591'
      ],
      correctAnswerIndex: 0,
      explanation: 'Presidential Decree 968, as amended, is the Probation Law of 1976.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'ca_005',
      subject: 'corrections',
      topic: 'Parole',
      questionText: 'Parole differs from probation in that parole:',
      options: [
        'Is granted before imprisonment',
        'Is granted after serving part of a prison sentence',
        'Does not require supervision',
        'Is the same as amnesty'
      ],
      correctAnswerIndex: 1,
      explanation: 'Parole is conditional release after serving a portion of prison sentence, while probation is granted instead of imprisonment.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'ca_006',
      subject: 'corrections',
      topic: 'Rehabilitation Programs',
      questionText: 'The primary goal of rehabilitation in corrections is:',
      options: [
        'Punishment of offenders',
        'Reintegration of offenders into society',
        'Isolation from society',
        'Revenue generation'
      ],
      correctAnswerIndex: 1,
      explanation: 'Rehabilitation aims to reform offenders and prepare them for successful reintegration into society.',
      difficulty: Difficulty.easy,
    ),
    Question(
      id: 'ca_007',
      subject: 'corrections',
      topic: 'Inmate Classification',
      questionText: 'Security classification of prisoners is primarily based on:',
      options: [
        'Age only',
        'Crime committed, sentence, and escape risk',
        'Educational attainment',
        'Financial status'
      ],
      correctAnswerIndex: 1,
      explanation: 'Security classification considers the nature of the offense, length of sentence, and potential escape risk.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'ca_008',
      subject: 'corrections',
      topic: 'Prison Security',
      questionText: 'Maximum security prisoners are those:',
      options: [
        'Serving sentences of 20 years to life',
        'With good behavior records',
        'About to be released',
        'Serving less than 3 years'
      ],
      correctAnswerIndex: 0,
      explanation: 'Maximum security classification includes prisoners serving long sentences and those with high escape risk.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'ca_009',
      subject: 'corrections',
      topic: 'Therapeutic Communities',
      questionText: 'A Therapeutic Community (TC) in corrections focuses on:',
      options: [
        'Punishment',
        'Drug rehabilitation through peer support',
        'Isolation',
        'Entertainment'
      ],
      correctAnswerIndex: 1,
      explanation: 'Therapeutic Communities use peer support and mutual self-help to treat substance abuse in correctional settings.',
      difficulty: Difficulty.medium,
    ),
    Question(
      id: 'ca_010',
      subject: 'corrections',
      topic: 'Institutional Corrections',
      questionText: 'BJMP stands for:',
      options: [
        'Bureau of Jail Management and Penology',
        'Bureau of Justice and Municipal Police',
        'Board of Jail Monitoring Program',
        'Bureau of Judicial Management and Planning'
      ],
      correctAnswerIndex: 0,
      explanation: 'BJMP is the Bureau of Jail Management and Penology, which manages city and municipal jails.',
      difficulty: Difficulty.easy,
    ),
  ];

  static List<Question> getAllQuestions() => _allQuestions;

  static List<Question> getQuestionsBySubject(String subjectId) {
    return _allQuestions.where((q) => q.subject == subjectId).toList();
  }

  static List<Question> getQuestionsByTopic(String subjectId, String topic) {
    return _allQuestions
        .where((q) => q.subject == subjectId && q.topic == topic)
        .toList();
  }

  static List<Question> getQuestionsByDifficulty(Difficulty difficulty) {
    return _allQuestions.where((q) => q.difficulty == difficulty).toList();
  }

  static int getQuestionCountBySubject(String subjectId) {
    return _allQuestions.where((q) => q.subject == subjectId).length;
  }
}
