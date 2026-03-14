import 'package:flutter/material.dart';

import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';

class RoomPickerDialog extends StatefulWidget {
  final String title;
  final bool Function(Room room)? roomFilter;

  const RoomPickerDialog({
    required this.title,
    this.roomFilter,
    super.key,
  });

  @override
  State<RoomPickerDialog> createState() => _RoomPickerDialogState();
}

class _RoomPickerDialogState extends State<RoomPickerDialog> {
  final TextEditingController _filterController = TextEditingController();

  String? selectedRoomId;

  void _toggleRoom(String roomId) {
    setState(() {
      selectedRoomId = roomId;
    });
  }

  void _confirmSelection() {
    final client = Matrix.of(context).client;
    final room = client.getRoomById(selectedRoomId!);
    context.pop(room);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    bool defaultFilter(Room room) =>
        !room.isSpace && room.membership == Membership.join;
    final roomFilter = widget.roomFilter ?? defaultFilter;
    final rooms =
        Matrix.of(context).client.rooms.where(roomFilter).toList();
    final filter = _filterController.text.trim().toLowerCase();
    return Scaffold(
      appBar: AppBar(
        leading: Center(child: CloseButton(onPressed: context.pop)),
        title: Text(widget.title),
      ),
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            floating: true,
            toolbarHeight: 72,
            scrolledUnderElevation: 0,
            backgroundColor: Colors.transparent,
            automaticallyImplyLeading: false,
            title: TextField(
              controller: _filterController,
              onChanged: (_) => setState(() {}),
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                contentPadding: EdgeInsets.zero,
                hintText: L10n.of(context).search,
                hintStyle: TextStyle(
                  color: theme.colorScheme.onPrimaryContainer,
                  fontWeight: FontWeight.normal,
                ),
                floatingLabelBehavior: FloatingLabelBehavior.never,
                prefixIcon: IconButton(
                  onPressed: () {},
                  icon: Icon(
                    Icons.search_outlined,
                    color: theme.colorScheme.onPrimaryContainer,
                  ),
                ),
              ),
            ),
          ),
          SliverList.builder(
            itemCount: rooms.length,
            itemBuilder: (context, i) {
              final room = rooms[i];
              final displayname = room.getLocalizedDisplayname(
                MatrixLocals(L10n.of(context)),
              );
              final value = selectedRoomId == room.id;
              final filterOut =
                  !displayname.toLowerCase().contains(filter);
              if (!value && filterOut) {
                return const SizedBox.shrink();
              }
              return Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16.0),
                child: Opacity(
                  opacity: filterOut ? 0.5 : 1,
                  child: CheckboxListTile.adaptive(
                    checkboxShape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(90),
                    ),
                    controlAffinity: ListTileControlAffinity.trailing,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppConfig.borderRadius,
                      ),
                    ),
                    secondary: Avatar(
                      mxContent: room.avatar,
                      name: displayname,
                      size: Avatar.defaultSize * 0.75,
                    ),
                    title: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      room.directChatMatrixID ??
                          L10n.of(context).countParticipants(
                            (room.summary.mJoinedMemberCount ?? 0) +
                                (room.summary.mInvitedMemberCount ?? 0),
                          ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    value: value,
                    onChanged: (_) => _toggleRoom(room.id),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      bottomNavigationBar: AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: selectedRoomId == null
            ? const SizedBox.shrink()
            : Material(
                elevation: 8,
                shadowColor: theme.appBarTheme.shadowColor,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: ElevatedButton(
                    onPressed: _confirmSelection,
                    child: Text(L10n.of(context).confirm),
                  ),
                ),
              ),
      ),
    );
  }
}
