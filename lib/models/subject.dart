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

// 2026 PRC Board Exam subjects with actual weights
class CriminologySubjects {
  static const List<Subject> all = [
    // Day 1
    Subject(
      id: 'criminal_jurisprudence',
      name: 'Criminal Jurisprudence',
      shortName: 'Crim Juris',
      description: 'Criminal Law Book I & II, Criminal Procedure, Evidence and Court Testimony',
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
      description: 'Police Organization, Operations, Intelligence, and Comparative Police System',
      icon: Icons.local_police,
      color: Color(0xFF1E3A5F),
      weight: 20,
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
      name: 'Criminalistics',
      shortName: 'Criminalistics',
      description: 'Personal Identification, Forensic Ballistics, Questioned Documents, Polygraph',
      icon: Icons.fingerprint,
      color: Color(0xFF1E3A5F),
      weight: 20,
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
      description: 'Criminal Investigation, Traffic Management, Special Crime Investigation',
      icon: Icons.search,
      color: Color(0xFF1E3A5F),
      weight: 15,
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
    // Day 3 - Updated based on 2026 TOS
    Subject(
      id: 'criminology',
      name: 'Criminology',
      shortName: 'Criminology',
      description: 'Theories, Human Behavior, Ethics, Juvenile Justice, Research',
      icon: Icons.psychology,
      color: Color(0xFF1E3A5F),
      weight: 15,
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
      description: 'Institutional and Non-Institutional Corrections, Rehabilitation',
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
