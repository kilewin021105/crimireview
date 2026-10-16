import 'package:flutter/material.dart';

class Subject {
  final String id;
  final String name;
  final String shortName;
  final String description;
  final IconData icon;
  final Color color;
  final int weight; // Percentage weight in board exam
  final List<String> topics;

  const Subject({
    required this.id,
    required this.name,
    required this.shortName,
    required this.description,
    required this.icon,
    required this.color,
    required this.weight,
    required this.topics,
  });
}

// The six Criminologist Licensure Examination subjects and their weights,
// per PRC Board of Criminology Resolution No. 01, s. 2021 (in force since
// the 2nd exam of 2022; confirmed by the PRC Program of Examination for
// February 4-6, 2026). RA 11131 Sec. 15 (2018) had an older table.
// The ids are internal keys used by saved progress and the question bank;
// they stay the same even where the official names changed.
class CriminologySubjects {
  static const List<Subject> all = [
    // Day 1
    Subject(
      id: 'criminal_jurisprudence',
      name: 'Criminal Law and Jurisprudence',
      shortName: 'Crim Law',
      description: 'Criminal Law Books 1 & 2, Evidence, Criminal Procedure and Court Testimony, Human Rights, the Philippine Criminal Justice System',
      icon: Icons.gavel,
      color: Color(0xFF1E3A5F),
      weight: 20,
      topics: [
        'Criminal Law Book I',
        'Criminal Law Book II',
        'Criminal Procedure',
        'Rules of Evidence',
        'Court Testimony',
        'Justifying Circumstances',
        'Exempting Circumstances',
        'Mitigating Circumstances',
        'Aggravating Circumstances',
        'Penalties and Punishment',
      ],
    ),
    Subject(
      id: 'law_enforcement',
      name: 'Law Enforcement Administration',
      shortName: 'Law Enforce',
      description: 'Law Enforcement Organization, Comparative Models in Policing, Industrial Security, Operations and Planning with Crime Mapping',
      icon: Icons.local_police,
      color: Color(0xFF1E3A5F),
      weight: 15,
      topics: [
        'Police Organization and Administration',
        'Police Planning',
        'Industrial Security Administration',
        'Police Patrol Operations',
        'Police Communication System',
        'Police Intelligence',
        'Police Personnel Management',
        'Police Records Management',
        'Comparative Police System',
      ],
    ),
    // Day 2
    Subject(
      id: 'criminalistics',
      name: 'Forensic Science',
      shortName: 'Forensic Sci',
      description: 'Forensic Photography, Personal Identification, Forensic Chemistry and Toxicology, Questioned Documents, Lie Detection, Ballistics',
      icon: Icons.fingerprint,
      color: Color(0xFF1E3A5F),
      weight: 15,
      topics: [
        'Personal Identification',
        'Police Photography',
        'Forensic Ballistics',
        'Questioned Documents Examination',
        'Polygraph and Lie Detection',
        'Legal Medicine',
        'Dactyloscopy',
        'DNA Analysis',
        'Forensic Chemistry',
      ],
    ),
    Subject(
      id: 'crime_detection',
      name: 'Crime Detection and Investigation',
      shortName: 'CDI',
      description: 'Criminal Investigation and Intelligence, Specialized Crime Investigation, Traffic, Fire and Arson, Drugs, Cybercrime',
      icon: Icons.search,
      color: Color(0xFF1E3A5F),
      weight: 20,
      topics: [
        'Fundamentals of Criminal Investigation',
        'Traffic Management',
        'Accident Investigation',
        'Special Crime Investigation',
        'Organized Crime Investigation',
        'Drug Education and Vice Control',
        'Fire Technology',
        'Arson Investigation',
        'Crime Scene Investigation',
      ],
    ),
    // Day 3
    Subject(
      id: 'criminology',
      name: 'Criminology',
      shortName: 'Criminology',
      description: 'Theories of Crime Causation, Human Behavior and Victimology, Ethics, Juvenile Justice, Criminological Research',
      icon: Icons.psychology,
      color: Color(0xFF1E3A5F),
      weight: 20,
      topics: [
        'Introduction to Criminology',
        'Theories of Crime Causation',
        'Human Behavior and Victimology',
        'Professional Conduct and Ethical Standards',
        'Juvenile Delinquency and Juvenile Justice',
        'Dispute Resolution and Crisis Management',
        'Character Formation and Nationalism',
        'Criminological Research',
      ],
    ),
    Subject(
      id: 'corrections',
      name: 'Correctional Administration',
      shortName: 'Corrections',
      description: 'Institutional and Non-Institutional Corrections, Therapeutic Modalities',
      icon: Icons.account_balance,
      color: Color(0xFF1E3A5F),
      weight: 10,
      topics: [
        'Institutional Corrections',
        'Non-Institutional Corrections',
        'Probation',
        'Parole',
        'Pardon and Amnesty',
        'Rehabilitation Programs',
        'Inmate Classification',
        'Prison Security',
        'Therapeutic Communities',
      ],
    ),
  ];

  static Subject getById(String id) {
    return all.firstWhere((s) => s.id == id);
  }
}
