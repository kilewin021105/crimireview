import 'package:flutter/material.dart';
import '../models/subject.dart';
import '../utils/page_transitions.dart';
import '../utils/responsive.dart';
import '../widgets/ui/ui.dart';
import 'flashcard_screen.dart';

/// Tab root for Flashcards: pick a subject, then study its deck.
///
/// `FlashcardScreen` itself needs a subject to know which questions to pull
/// from `QuestionRepository`, so this screen is the subject picker in front
/// of it -- the same role `SubjectsScreen` plays for the Quiz tab. Pushing
/// `FlashcardScreen` via [Navigator] (rather than swapping it directly into
/// the tab's `IndexedStack`) keeps its existing back button working exactly
/// as it already does everywhere else it's used.
class FlashcardsHomeScreen extends StatelessWidget {
  const FlashcardsHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final padding = Responsive.horizontalPadding(context);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(padding, 16, padding, 28),
          child: ContentWidth(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const PageHeader(
                  title: 'Flashcards',
                  subtitle: 'Choose a deck to review',
                ),
                const SizedBox(height: 16),
                const InlineBanner(
                  tone: BannerTone.neutral,
                  icon: Icons.touch_app_rounded,
                  message: 'Tap a card to flip it and see the answer. Swipe to move to the next card.',
                ),
                const SizedBox(height: 20),
                LayoutBuilder(builder: (context, c) {
                  final columns = c.maxWidth >= 560 ? 3 : 2;
                  return GridView.builder(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    physics: const NeverScrollableScrollPhysics(),
                    gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                      crossAxisCount: columns,
                      mainAxisSpacing: 14,
                      crossAxisSpacing: 12,
                      mainAxisExtent: 178,
                    ),
                    itemCount: CriminologySubjects.all.length,
                    itemBuilder: (context, index) => Appear(
                      index: index,
                      child: _DeckTile(subject: CriminologySubjects.all[index]),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A subject's deck: the front card with two cards peeking out behind it.
class _DeckTile extends StatelessWidget {
  final Subject subject;

  const _DeckTile({required this.subject});

  @override
  Widget build(BuildContext context) {
    final p = context.palette;
    final text = context.textStyles;
    final icon = AppTheme.subjectIcons[subject.id] ?? Icons.book_rounded;
    final color = AppColors.subjectColor(subject.id);

    Widget layer(double inset, double alpha) => Positioned(
          left: inset,
          right: inset,
          top: 0,
          bottom: 0,
          child: Container(
            decoration: BoxDecoration(
              color: Color.alphaBlend(color.withValues(alpha: alpha), p.surface),
              borderRadius: BorderRadius.circular(AppSpace.radiusLg),
              border: Border.all(color: p.border),
            ),
          ),
        );

    return Stack(
      children: [
        layer(14, context.isDarkMode ? 0.18 : 0.10),
        Positioned.fill(
          top: 0,
          bottom: 6,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Container(
              decoration: BoxDecoration(
                color: Color.alphaBlend(color.withValues(alpha: context.isDarkMode ? 0.12 : 0.06), p.surface),
                borderRadius: BorderRadius.circular(AppSpace.radiusLg),
                border: Border.all(color: p.border),
              ),
            ),
          ),
        ),
        Positioned.fill(
          bottom: 12,
          child: AppCard(
            padding: const EdgeInsets.all(14),
            onTap: () {
              Navigator.push(
                context,
                SlidePageRoute(page: FlashcardScreen(subject: subject)),
              );
            },
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    IconBadge(icon: icon, color: color, size: 40, iconSize: 21),
                    const Spacer(),
                    Icon(Icons.style_rounded, size: 18, color: p.textTertiary),
                  ],
                ),
                const Spacer(),
                Text(
                  subject.shortName,
                  style: text.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${subject.topics.length} topics',
                  style: text.bodySmall,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Text('Study deck', style: text.labelMedium?.copyWith(color: color)),
                    const SizedBox(width: 2),
                    Icon(Icons.arrow_forward_rounded, size: 15, color: color),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
