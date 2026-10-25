# Sources for the TOS-aligned content

Everything in `assets/tos/tos_2024.json`, `content/tos/bank/` and the study modules on branch `tos-aligned-bank` follows these official documents. Checked on 2026-10-24.

## Table of Specifications (TOS)

- **PRB of Criminology Resolution No. 02, Series of 2024**: *Enhanced Tables of Specifications for the Subjects in the Licensure Examination for Criminologists Based on the Standardized Format Aligned with the Philippine Qualifications Framework*.
  - Done April 16, 2024. Published in the Business Mirror on April 19, 2024. Effective May 5, 2024.
  - Applies from the **July 2024** Licensure Examination for Criminologists onward.
  - Resolution: https://www.prc.gov.ph/sites/default/files/2024-02%20Published%20%281%29%20%281%29.pdf
  - Each annex is headed "Table of Specifications, Board of Criminology, as of January 22, 2024, PQF Level 6":
    - Criminal Law and Jurisprudence (20%): https://www.prc.gov.ph/sites/default/files/ANNEX%20A_CLJ.pdf
    - Law Enforcement Administration (15%): https://www.prc.gov.ph/sites/default/files/ANNEX%20A_LEA.pdf
    - Forensic Science (15%): https://www.prc.gov.ph/sites/default/files/ANNEX%20A_Forensic%20Science.pdf
    - Crime Detection and Investigation (20%): https://www.prc.gov.ph/sites/default/files/ANNEX%20A_CDI.pdf
    - Criminology (20%): https://www.prc.gov.ph/sites/default/files/ANNEX%20A_Criminology.pdf
    - Correctional Administration (10%): https://www.prc.gov.ph/sites/default/files/ANNEX%20A_Corad_0.pdf
- **PRB of Criminology Resolution No. 06, Series of 2025**: *Amendments to Board Resolution No. 02 (s. 2024) in the Subject Area of Criminology, Specifically on the Topic of Professional Conduct and Ethical Standards*.
  - Done June 26, 2025. Published in the Business Mirror on June 30, 2025. Effective July 16, 2025.
  - Applies from the **August 2025** exam onward.
  - It replaces Criminology Topic 4 with four competencies on the Code of Ethical and Professional Conduct (15 items).
  - https://www.prc.gov.ph/sites/default/files/2025-06%20published%20Amendments%20To%20Board%20Resolution%20No.%2002%20%28S.%202024%29%20in%20the%20Subject%20Area%20of%20Criminology.pdf
- **Subjects and weights**: PRB of Criminology Resolution No. 01, Series of 2021. https://www.prc.gov.ph/sites/default/files/2021-01%20published%20%281%29.pdf

**How the TOS file was made:** `tools/tos/parse_annex.py` reads each annex PDF and places every number in its Bloom's taxonomy column by its position on the page. `tools/tos/build_tos.py` then joins rows that run across page breaks, applies Resolution No. 06 s. 2025, and checks the counts:
- every competency's Bloom split equals its items;
- every topic equals the sum of its competencies;
- every subject equals 100.

The PDFs have two inconsistencies of their own, and the competency rows were followed in both:
- the Forensic Science and Correctional Administration header rows give Bloom totals that differ from their own topic rows;
- the LEA total row says "20%" although the subject weight is 15%.

## Code of Ethical and Professional Conduct of Philippine Registered Criminologists

- **PRB of Criminology Resolution No. 07, Series of 2024**: done December 17, 2024. Published in the Business Mirror on January 15, 2025. Effective January 31, 2025.
- https://www.prc.gov.ph/sites/default/files/2024-07%20published%20coe%20Crim.pdf
- It is the basis of Criminology Topic 4 (Res. No. 06 s. 2025). Its structure, transcribed from the scanned PDF:
  - **Chapter I, Introduction.** Section 1 defines:
    - Accredited Integrated Professional Organization (AIPO): the one and only national organization of Criminologists accredited by the Board and the Commission; membership is automatic and mandatory;
    - Certificate of Registration (COR);
    - Client: a natural or juridical person who engages the professional services of a Criminologist;
    - Malpractice of Profession: an improper act in the practice, or failure to competently perform one's duties within the legal and ethical standards;
    - Practice of Profession;
    - Professional Identification Card (PIC);
    - Registered Criminologist (RCrim): a natural person with a valid COR and an updated PIC;
    - Temporary/Special Permit: for Criminologists from other countries, under Sec. 30 of the IRR of R.A. 11131;
    - Certificate of Good Standing (COGS): proof of bona fide AIPO membership, required for renewal of the PIC.
  - **Chapter II, Duties to the Society:**
    - Sec. 1, Respect for Law: uphold the Constitution and obey the laws; legal, moral and ethical conduct; the rule of law; human rights.
    - Sec. 2, Public Service and Social Responsibility: public interest over personal interest; dignity, fairness, sincerity; role model; prompt, courteous and efficient service without discrimination; contribution through research, instruction, extension and practice.
    - Sec. 3, Personal Integrity and Honesty: integrity in all facets of life; no misrepresentation of qualifications; avoid conflicts of interest and the appearance of impropriety.
  - **Chapter III, Duties to the Criminology Profession:**
    - Sec. 1, Advocacy: protect the profession from unqualified persons; enthusiasm and dedication; observe the Oath of Professionals and the Oath of Membership of the AIPO. Law enforcers follow the Code of Ethics for Law Enforcement Officials and their agency codes. Researchers do not plagiarize. Forensic practitioners stay committed to scientific principles and truth. Industrial security practitioners protect life and property. Criminologists act professionally, take part in PRC, Board and AIPO programs, and stay independent from pressure.
    - Sec. 2, Demeanor towards Professional Colleagues: courtesy, fairness and candor; recognize expertise; collaborate; no abusive language; do not malign fellow Criminologists.
    - Sec. 3, Commitment to Life-long Learning: CPD; re-skilling and up-skilling; micro-credentialing and specialized certification; career progression.
  - **Chapter IV, Duties to Clients:**
    - Sec. 1, Demeanor towards Clients: fairness; in the academe, the welfare of both students and the institution; in correctional institutions, humane treatment of persons deprived of liberty; in private practice, reasonable fees; utmost confidentiality.
    - Sec. 2, Professionalism in the Practice:
      - no prohibited acts under Secs. 22 and 37 of R.A. 11131;
      - no unlawful, dishonest, immoral or deceitful acts;
      - no plagiarism;
      - no false or misleading claims about qualifications;
      - no delegating exclusively criminological tasks to non-criminologists;
      - no conflicts of interest;
      - no practice with an expired, suspended or revoked COR, PIC or permit;
      - no using another Criminologist's seal, pin, badge, title, COR or PIC;
      - no abetting illegal practice;
      - no securing documents by misrepresentation;
      - no impersonating another Criminologist.
  - **Chapter V, Miscellaneous Provisions:**
    - Sec. 1: violations of **Chapter IV** are grave offenses, punished by suspension for two (2) years or revocation of the license. Other violations may be grave depending on gravity; otherwise they are less grave offenses, punished by reprimand and/or suspension of up to two (2) years. These are without prejudice to civil, criminal and administrative liability under the RPC, Civil Code, R.A. 11131, R.A. 6713, R.A. 3019 and other laws. The procedure follows the Commission's rules on administrative investigation.
    - Sec. 2: separability. Sec. 3: effectivity, fifteen (15) days after publication.

## How the existing questions were mapped

`assets/tos/topic_map.json` sends each topic name used before the alignment to a TOS topic, by topic name and by the wording of the questions (17 single questions of mixed topics have their own entry). Where the TOS places a topic in another subject, the questions move there; for example Legal Medicine belongs to Crime Detection and Investigation, Topic 2, and Police Intelligence to CDI Topic 1. Police radio codes and police psychology are not in the TOS, so those 11 questions are deactivated, not deleted. The old questions are linked to a TOS **topic** (e.g. `CLJ-3`), not to a competency: faculty can refine the link in the question editor.

## Status of the generated content

The questions in `content/tos/bank/` and the study modules were **written with AI assistance (Claude) from the TOS competencies and the laws they name**. They are drafts: they enter the database **inactive**, and students see a question only after a faculty member reviews and approves it (Admin Panel → TOS coverage). The criminology faculty acting as content validators are responsible for checking every item against the current laws and rules before approval.
