import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../comment_tree.dart';
import '../l10n/l10n.dart';
import '../pages/full_post/full_post.dart';
import '../stores/accounts_store.dart';
import '../util/observer_consumers.dart';
import 'bottom_modal.dart';
import 'bottom_safe.dart';
import 'comment/comment.dart';
import 'post/full_post_store.dart';

/// Manages comments section, sorts them
class CommentSection extends StatelessWidget {
  static const sortPairs = {
    CommentSortType.hot: [Icons.whatshot, L10nStrings.hot],
    CommentSortType.new_: [Icons.new_releases, L10nStrings.new_],
    CommentSortType.old: [Icons.calendar_today, L10nStrings.old],
    CommentSortType.top: [Icons.trending_up, L10nStrings.top],
    CommentSortType.chat: [Icons.chat, L10nStrings.chat],
  };

  const CommentSection({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return ObserverBuilder<FullPostStore>(
      builder: (context, store) {
        // error & spinner handling
        if (store.fullPostView == null) {
          if (store.fullPostState.errorTerm != null) {
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 30),
              child: FailedToLoad(
                  message: 'Comments failed to load',
                  refresh: () => store.refresh(context
                      .read<AccountsStore>()
                      .defaultUserDataFor(store.instanceHost)
                      ?.jwt)),
            );
          } else {
            return const Padding(
              padding: EdgeInsets.only(top: 40),
              child: Center(child: CircularProgressIndicator()),
            );
          }
        }

        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 15),
              child: Row(
                children: [
                  OutlinedButton(
                    onPressed: () {
                      showBottomModal(
                        title: 'sort by',
                        context: context,
                        builder: (context) => Column(
                          children: [
                            for (final e in sortPairs.entries)
                              ListTile(
                                leading: Icon(e.value[0] as IconData),
                                title: Text((e.value[1] as String).tr(context)),
                                trailing: store.sorting == e.key
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () {
                                  Navigator.of(context).pop();
                                  store.updateSorting(e.key);
                                },
                              )
                          ],
                        ),
                      );
                    },
                    child: Row(
                      children: [
                        Text((sortPairs[store.sorting]![1] as String)
                            .tr(context)),
                        const Icon(Icons.arrow_drop_down),
                      ],
                    ),
                  ),
                  const Spacer(),
                ],
              ),
            ),
            // sorting menu goes here
            if (store.fullPostView!.comments.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 50),
                child: Text(
                  'no comments yet',
                  style: TextStyle(fontStyle: FontStyle.italic),
                ),
              )
            else ...[
              for (final com in store.newComments)
                CommentWidget.fromCommentView(
                  com,
                  detached: false,
                  key: ValueKey(com),
                ),
              if (store.sorting == CommentSortType.chat)
                for (final com in store.fullPostView!.comments)
                  CommentWidget.fromCommentView(
                    com,
                    detached: false,
                    key: ValueKey(com),
                  )
              else
                for (final com in store.sortedCommentTree!)
                  CommentWidget(
                    com,
                    key: ValueKey(com),
                  ),
              const BottomSafe(
                  kMinInteractiveDimension + kFloatingActionButtonMargin),
            ]
          ],
        );
      },
    );
  }
}
