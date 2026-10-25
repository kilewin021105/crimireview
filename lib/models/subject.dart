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
//
// [Subject.topics] are the topics of the PRC Tables of Specifications (Board
// Res. No. 02 s. 2024, as amended by Res. No. 06 s. 2025), in TOS order and
// with the TOS titles, which the question bank, the study modules and the
// student's topic mastery all use. test/tos_test.dart checks them against
// assets/tos/tos_2024.json.
class CriminologySubjects {
  static const List<Subject> all = [
    // Day 1
    Subject(
      id: 'criminal_jurisprudence',
      name: 'Criminal Law and Jurisprudence',
      shortName: 'Crim Law',
      description: 'Criminal Justice System, Human Rights, Criminal Law Books 1 and 2, Criminal Evidence, Criminal Procedure and Court Testimony',
      icon: Icons.gavel,
      color: Color(0xFF1E3A5F),
      weight: 20,
      topics: [
        'Introduction to the Criminal Justice System',
        'Human Rights Education',
        'Criminal Law (Book 1)',
        'Criminal Law (Book 2)',
        'Criminal Evidence',
        'Criminal Procedure and Court Testimony',
      ],
    ),
    Subject(
      id: 'law_enforcement',
      name: 'Law Enforcement Administration',
      shortName: 'Law Enforce',
      description: 'Law Enforcement Organization, Comparative Policing, Industrial Security, Operations and Planning with Crime Mapping, Character Formation',
      icon: Icons.local_police,
      color: Color(0xFF1E3A5F),
      weight: 15,
      topics: [
        'Law Enforcement Organization and Administration (Inter-Agency Approach)',
        'Comparative Models in Policing',
        'Introduction to Industrial Security Concepts',
        'Law Enforcement Operations and Planning with Crime Mapping',
        'Character Formation 1 - Nationalism and Patriotism',
        'Character Formation 2 - Leadership, Decision Making, Management and Administration',
      ],
    ),
    // Day 2
    Subject(
      id: 'criminalistics',
      name: 'Forensic Science',
      shortName: 'Forensic Sci',
      description: 'Personal Identification, Forensic Photography, Chemistry and Toxicology, Questioned Documents, Lie Detection, Ballistics, Report Writing',
      icon: Icons.fingerprint,
      color: Color(0xFF1E3A5F),
      weight: 15,
      topics: [
        'Personal Identification Techniques',
        'Forensic Photography',
        'Forensic Chemistry and Toxicology',
        'Questioned Documents Examination',
        'Lie Detection Techniques',
        'Forensic Ballistics',
        'Forensic Report Writing and Laboratory Safety',
      ],
    ),
    Subject(
      id: 'crime_detection',
      name: 'Crime Detection and Investigation',
      shortName: 'CDI',
      description: 'Investigation and Intelligence, Specialized Crime Investigation, Traffic, Fire and Arson, Vice and Drugs, Technical Writing, Cybercrime and Environmental Laws',
      icon: Icons.search,
      color: Color(0xFF1E3A5F),
      weight: 20,
      topics: [
        'Fundamentals of Criminal Investigation and Intelligence',
        'Specialized Crime Investigation 1 with Legal Medicine',
        'Specialized Crime Investigation 2 with Interview and Interrogation',
        'Traffic Management and Accident Investigation with Driving',
        'Fire Protection and Arson Investigation',
        'Vice and Drug Education and Control',
        'Technical Writing 1 and 2 (Legal forms and Police Report writing)',
        'Introduction to Cybercrime and Environmental Laws',
      ],
    ),
    // Day 3
    Subject(
      id: 'criminology',
      name: 'Criminology',
      shortName: 'Criminology',
      description: 'Introduction to Criminology, Theories of Crime Causation, Human Behavior and Victimology, Professional Ethics, Juvenile Justice, Dispute Resolution, Research',
      icon: Icons.psychology,
      color: Color(0xFF1E3A5F),
      weight: 20,
      topics: [
        'Introduction to Criminology',
        'Theories of Crime Causation',
        'Human Behavior and Victimology',
        'Professional Conduct and Ethical Standards for Criminologists',
        'Juvenile Delinquency and Juvenile Justice',
        'Dispute Resolution and Crisis/Incident Management',
        'Criminological Research 1 and 2',
      ],
    ),
    Subject(
      id: 'corrections',
      name: 'Correctional Administration',
      shortName: 'Corrections',
      description: 'Institutional Correction, Non-Institutional Correction, Therapeutic Modalities',
      icon: Icons.account_balance,
      color: Color(0xFF1E3A5F),
      weight: 10,
      topics: [
        'Institutional Correction',
        'Non-Institutional Correction',
        'Therapeutic Modalities',
      ],
    ),
  ];

  static Subject getById(String id) {
    return all.firstWhere((s) => s.id == id);
  }
}
