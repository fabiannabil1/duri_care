import 'package:duri_care/core/resources/resources.dart';
import 'package:flutter/material.dart';

class RoleBadge extends StatelessWidget {
  const RoleBadge({super.key, required this.role});
  final String role;

  @override
  Widget build(BuildContext context) {
    final lowerRole = role.toLowerCase();
    String displayText;
    Color badgeColor;
    if (lowerRole == 'owner') {
      displayText = 'Owner';
      badgeColor = AppColor.greenSecondary;
    } else if (lowerRole == 'user') {
      displayText = 'User';
      badgeColor = AppColor.yellowPrimary;
    } else {
      displayText = role;
      badgeColor = Colors.grey;
    }

    return Container(
      margin: const EdgeInsets.only(left: 6),
      width: 50,
      height: 16,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: badgeColor,
      ),
      alignment: Alignment.center,
      child: Text(
        displayText,
        style: Theme.of(context).textTheme.labelMedium!.copyWith(
          color: Colors.white,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          decoration: TextDecoration.none,
        ),
      ),
    );
  }
}
