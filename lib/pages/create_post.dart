import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:image_picker/image_picker.dart';
import 'package:lemmy_api_client/lemmy_api_client.dart';

import '../hooks/delayed_loading.dart';
import '../hooks/image_picker.dart';
import '../hooks/logged_in_action.dart';
import '../hooks/memo_future.dart';
import '../hooks/stores.dart';
import '../util/extensions/api.dart';
import '../util/goto.dart';
import '../util/pictrs.dart';
import '../util/spaced.dart';
import '../widgets/markdown_text.dart';
import 'full_post.dart';

/// Fab that triggers the [CreatePost] modal
class CreatePostFab extends HookWidget {
  @override
  Widget build(BuildContext context) {
    final loggedInAction = useLoggedInAction(null, any: true);

    return FloatingActionButton(
      child: Icon(Icons.add),
      onPressed: loggedInAction((_) => showCupertinoModalPopup(
          context: context, builder: (_) => CreatePost())),
    );
  }
}

/// Modal for creating a post to some community in some instance
class CreatePost extends HookWidget {
  final CommunityView community;

  final GlobalKey<ScaffoldState> scaffoldKey = GlobalKey();

  CreatePost() : community = null;
  CreatePost.toCommunity(this.community);

  @override
  Widget build(BuildContext context) {
    final urlController = useTextEditingController();
    final titleController = useTextEditingController();
    final bodyController = useTextEditingController();
    final accStore = useAccountsStore();
    final selectedInstance =
        useState(community?.instanceUrl ?? accStore.loggedInInstances.first);
    final selectedCommunity = useState(community);
    final showFancy = useState(false);
    final nsfw = useState(false);
    final delayed = useDelayedLoading();
    final imagePicker = useImagePicker();
    final imageUploadLoading = useState(false);
    final pictrsDeleteToken = useState<PictrsUploadFile>(null);

    final allCommunitiesSnap = useMemoFuture(
      () => LemmyApi(selectedInstance.value)
          .v1
          .listCommunities(
            sort: SortType.hot,
            limit: 9999,
            auth: accStore.defaultTokenFor(selectedInstance.value).raw,
          )
          .then(
        (value) {
          value.sort((a, b) => a.name.compareTo(b.name));
          return value;
        },
      ),
      [selectedInstance.value],
    );

    uploadPicture() async {
      try {
        final pic = await imagePicker.getImage(source: ImageSource.gallery);
        // pic is null when the picker was cancelled
        if (pic != null) {
          imageUploadLoading.value = true;

          final pictrs = LemmyApi(selectedInstance.value).pictrs;
          final upload = await pictrs.upload(pic.path);

          pictrsDeleteToken.value = upload.files[0];
          urlController.text =
              pathToPictrs(selectedInstance.value, upload.files[0].file);
        }
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        scaffoldKey.currentState
            .showSnackBar(SnackBar(content: Text('Failed to upload image')));
      } finally {
        imageUploadLoading.value = false;
      }
    }

    removePicture() {
      LemmyApi(selectedInstance.value)
          .pictrs
          .delete(pictrsDeleteToken.value)
          .catchError((_) {});

      pictrsDeleteToken.value = null;
      urlController.text = '';
    }

    // TODO: use drop down from AddAccountPage
    final instanceDropdown = InputDecorator(
      decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(vertical: 1, horizontal: 20),
          border: OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedInstance.value,
          onChanged: (val) => selectedInstance.value = val,
          items: accStore.loggedInInstances
              .map((instance) => DropdownMenuItem(
                    value: instance,
                    child: Text(instance),
                  ))
              .toList(),
        ),
      ),
    );

    // TODO: use lazy autocomplete
    final communitiesDropdown = InputDecorator(
      decoration: const InputDecoration(
          contentPadding: EdgeInsets.symmetric(vertical: 1, horizontal: 20),
          border: OutlineInputBorder()),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<String>(
          value: selectedCommunity.value?.name,
          hint: Text('Community'),
          onChanged: (val) => selectedCommunity.value =
              allCommunitiesSnap.data.firstWhere((e) => e.name == val),
          items: allCommunitiesSnap.hasData
              ? allCommunitiesSnap.data
                  .map((e) => DropdownMenuItem(
                        value: e.name,
                        child: Text(e.name),
                      ))
                  .toList()
              : [
                  DropdownMenuItem(
                    value: '',
                    child: CircularProgressIndicator(),
                  )
                ],
        ),
      ),
    );

    final url = Row(children: [
      Expanded(
        child: TextField(
          enabled: pictrsDeleteToken.value == null,
          controller: urlController,
          decoration: InputDecoration(
              border: OutlineInputBorder(),
              labelText: 'URL',
              suffixIcon: Icon(Icons.link)),
        ),
      ),
      SizedBox(width: 5),
      IconButton(
        icon: imageUploadLoading.value
            ? CircularProgressIndicator()
            : Icon(pictrsDeleteToken.value == null
                ? Icons.add_photo_alternate
                : Icons.close),
        onPressed:
            pictrsDeleteToken.value == null ? uploadPicture : removePicture,
        tooltip:
            pictrsDeleteToken.value == null ? 'Add picture' : 'Delete picture',
      )
    ]);

    final title = TextField(
      controller: titleController,
      minLines: 1,
      maxLines: 2,
      decoration:
          InputDecoration(border: OutlineInputBorder(), labelText: 'Title'),
    );

    final body = IndexedStack(
      index: showFancy.value ? 1 : 0,
      children: [
        TextField(
          controller: bodyController,
          keyboardType: TextInputType.multiline,
          maxLines: null,
          minLines: 5,
          textAlignVertical: TextAlignVertical.top,
          decoration:
              InputDecoration(border: OutlineInputBorder(), labelText: 'Body'),
        ),
        Padding(
          padding: const EdgeInsets.all(16),
          child: MarkdownText(
            bodyController.text,
            instanceUrl: selectedInstance.value,
          ),
        ),
      ],
    );

    handleSubmit() async {
      if (selectedCommunity.value == null || titleController.text.isEmpty) {
        scaffoldKey.currentState.showSnackBar(SnackBar(
          content: Text('Choosing a community and a title is required'),
        ));
        return;
      }

      final api = LemmyApi(selectedInstance.value).v1;

      final token = accStore.defaultTokenFor(selectedInstance.value);

      delayed.start();
      try {
        final res = await api.createPost(
            url: urlController.text.isEmpty ? null : urlController.text,
            body: bodyController.text.isEmpty ? null : bodyController.text,
            nsfw: nsfw.value,
            name: titleController.text,
            communityId: selectedCommunity.value.id,
            auth: token.raw);
        goToReplace(context, (_) => FullPostPage.fromPostView(res));
        return;
        // ignore: avoid_catches_without_on_clauses
      } catch (e) {
        scaffoldKey.currentState
            .showSnackBar(SnackBar(content: Text('Failed to post')));
      }
      delayed.cancel();
    }

    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: Navigator.of(context).pop,
        ),
        actions: [
          IconButton(
            icon: Icon(showFancy.value ? Icons.build : Icons.brush),
            onPressed: () => showFancy.value = !showFancy.value,
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: EdgeInsets.all(5),
          children: spaced(5, [
            instanceDropdown,
            communitiesDropdown,
            url,
            title,
            body,
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                GestureDetector(
                  onTap: () => nsfw.value = !nsfw.value,
                  child: Row(
                    children: [
                      Checkbox(
                        value: nsfw.value,
                        onChanged: (val) => nsfw.value = val,
                      ),
                      Text('NSFW')
                    ],
                  ),
                ),
                FlatButton(
                  onPressed: delayed.pending ? () {} : handleSubmit,
                  child: delayed.loading
                      ? CircularProgressIndicator()
                      : Text('post'),
                )
              ],
            ),
          ]),
        ),
      ),
    );
  }
}