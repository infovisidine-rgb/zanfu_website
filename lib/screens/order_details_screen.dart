import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import '../controllers/order_controller.dart';
import '../utils/app_colors.dart';
import '../utils/responsive_helper.dart';
import '../widgets/custom_header.dart';
import '../widgets/flame_text.dart';
import '../widgets/product_image_container.dart';

class OrderDetailsScreen extends StatelessWidget {
  final OrderModel order;

  const OrderDetailsScreen({super.key, required this.order});

  bool _shouldShowRiderDetails(OrderModel order) {
    final type = order.orderType.trim().toLowerCase();
    final isPickup = type.contains('pickup') || type.contains('takeaway');
    final isDineIn = type.contains('dine');
    if (isPickup || isDineIn) return false;

    final s = order.status.toLowerCase();
    // Do not show rider details once order is delivered or cancelled / declined
    if (s.contains('delivered') ||
        s.contains('cancel') ||
        s.contains('decline') ||
        s.contains('reject')) {
      return false;
    }

    final hasRiderName = order.riderName.trim().isNotEmpty;
    final hasRiderPhone = order.riderPhone.trim().isNotEmpty;
    return hasRiderName || hasRiderPhone;
  }

  Widget _buildRiderDetailsCard(BuildContext context, OrderModel order) {
    final name = order.riderName.trim().isNotEmpty
        ? order.riderName.trim()
        : 'Assigned Rider';
    final phone = order.riderPhone.trim();

    final label = _labelStyle(context);
    final value = _valueStyle(context);

    return _buildInfoCard(
      context: context,
      title: 'Rider Details',
      showCheck: false,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.two_wheeler_rounded,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(name, style: value),
                if (phone.isNotEmpty) ...[
                  const SizedBox(height: 3),
                  Text(phone, style: label),
                ],
              ],
            ),
          ),
          if (phone.isNotEmpty) ...[
            const SizedBox(width: 8),
            InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () async {
                final cleaned = phone.replaceAll(RegExp(r'[^\d+]'), '');
                if (cleaned.isNotEmpty) {
                  final uri = Uri(scheme: 'tel', path: cleaned);
                  try {
                    await launchUrl(uri);
                  } catch (e) {
                    debugPrint('Error launching rider phone: $e');
                  }
                }
              },
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.green.shade600,
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.phone_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  int _parsePrice(String priceStr) {
    final match = RegExp(r'\d+').firstMatch(priceStr);
    return match != null ? int.parse(match.group(0)!) : 0;
  }

  TextStyle _labelStyle(BuildContext context) => TextStyle(
        fontSize: ResponsiveHelper.isWide(context) ? 14.5 : 13.5,
        fontWeight: FontWeight.w500,
        color: AppColors.textSecondary,
        height: 1.45,
      );

  TextStyle _valueStyle(BuildContext context) => TextStyle(
        fontSize: ResponsiveHelper.isWide(context) ? 15 : 14,
        fontWeight: FontWeight.w600,
        color: AppColors.textPrimary,
        height: 1.45,
      );

  TextStyle _titleStyle(BuildContext context) => TextStyle(
        fontSize: ResponsiveHelper.isWide(context) ? 16.5 : 15,
        fontWeight: FontWeight.bold,
        color: AppColors.primary,
      );

  @override
  Widget build(BuildContext context) {
    final isPickup = order.orderType == 'Pickup';
    final isDineIn = order.orderType == 'Dine In';
    final isDelivery = !isPickup && !isDineIn;
    final branchLabel = order.branchName.trim().isNotEmpty
        ? order.branchName.trim()
        : 'restaurant';
    final label = _labelStyle(context);
    final value = _valueStyle(context);
    final title = _titleStyle(context);

    final Widget addressChild;
    if (isPickup) {
      addressChild = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Pickup from $branchLabel', style: value),
          if (order.branchAddress.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(order.branchAddress.trim(), style: label),
          ],
        ],
      );
    } else if (isDineIn) {
      addressChild = Text(
        order.tableNumber.isNotEmpty
            ? 'Dine In - Table ${order.tableNumber}'
            : 'Dine In',
        style: value,
      );
    } else {
      addressChild = Text(
        order.deliveryAddress.isNotEmpty
            ? order.deliveryAddress
            : 'No address provided',
        style: value,
      );
    }

    final leftColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildInfoCard(
          context: context,
          title: order.orderType == 'Dine In'
              ? 'Dine In'
              : isPickup
                  ? 'Pickup'
                  : 'Delivered To',
          child: addressChild,
        ),
        if (!isPickup && order.orderType != 'Dine In') ...[
          const SizedBox(height: 14),
          _buildInfoCard(
            context: context,
            title: 'Payment Method',
            child: Text('Cash on Delivery.', style: value),
          ),
        ],
        if (isDelivery && order.deliveryInstructions.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildInfoCard(
            context: context,
            title: 'Delivery Instructions',
            showCheck: false,
            child: Text(order.deliveryInstructions.trim(), style: label),
          ),
        ],
        if (order.specialInstructions.trim().isNotEmpty) ...[
          const SizedBox(height: 14),
          _buildInfoCard(
            context: context,
            title: 'Special Instructions',
            showCheck: false,
            child: Text(order.specialInstructions.trim(), style: label),
          ),
        ],
        const SizedBox(height: 14),
        _buildInfoCard(
          context: context,
          title: 'Order Status',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(order.status, style: value),
              if (order.hasStatusReason) ...[
                const SizedBox(height: 8),
                Text(order.statusReason.trim(), style: label),
              ],
            ],
          ),
          showCheck: false,
        ),
        if (_shouldShowRiderDetails(order)) ...[
          const SizedBox(height: 14),
          _buildRiderDetailsCard(context, order),
        ],
      ],
    );

    final rightColumn = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Items (${order.items.length})', style: title),
        const SizedBox(height: 10),
        ...order.items.map((i) => _buildItemCard(context, i)),
        const SizedBox(height: 16),
        _buildBillSummary(context),
      ],
    );

    final wide = ResponsiveHelper.isWide(context);

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: CustomHeader(
        title: order.orderId,
        subtitle: 'Order Details',
        showBackButton: true,
        showCartIcon: false,
        titleSize: wide ? 20 : 17,
      ),
      body: wide
          ? Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(child: leftColumn),
                  ),
                  const SizedBox(width: 24),
                  Expanded(
                    child: SingleChildScrollView(child: rightColumn),
                  ),
                ],
              ),
            )
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  leftColumn,
                  const SizedBox(height: 20),
                  rightColumn,
                ],
              ),
            ),
    );
  }

  Widget _buildInfoCard({
    required BuildContext context,
    required String title,
    required Widget child,
    bool showCheck = true,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: _titleStyle(context)),
                const SizedBox(height: 8),
                child,
              ],
            ),
          ),
          if (showCheck) ...[
            const SizedBox(width: 12),
            _greenCheck(),
          ],
        ],
      ),
    );
  }

  Widget _greenCheck() {
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.green.shade50,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.check_rounded, color: Colors.green.shade600, size: 16),
    );
  }

  Widget _buildBillSummary(BuildContext context) {
    final type = order.orderType.trim().toLowerCase();
    final isDelivery = !type.contains('pickup') &&
        !type.contains('takeaway') &&
        !type.contains('dine');
    final isDineIn = type.contains('dine');
    final showFee = isDelivery && order.deliveryFee != null;
    final feeLabel = showFee
        ? 'PKR ${order.deliveryFee!.round()}'
        : 'To be Calculated';
    final showServiceCharge = isDineIn && order.serviceCharge != null;
    final serviceChargeLabel = showServiceCharge
        ? 'PKR ${order.serviceCharge!.round()}'
        : 'To be Calculated';
    final tax = order.tax;
    final taxLabel = tax > 0 ? 'PKR ${tax.round()}' : 'Included';
    final itemsPrice =
        (order.totalAmount - (tax > 0 ? tax : 0)).clamp(0, double.infinity);
    final grandTotal = order.totalAmount +
        (isDelivery ? (order.deliveryFee ?? 0) : 0) +
        (isDineIn ? (order.serviceCharge ?? 0) : 0);

    final label = _labelStyle(context);
    final value = _valueStyle(context);
    final title = _titleStyle(context);
    final totalSize = ResponsiveHelper.isWide(context) ? 16.0 : 15.0;

    Widget billRow(String l, String v, {bool bold = false}) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            l,
            style: bold ? value.copyWith(fontWeight: FontWeight.bold) : label,
          ),
          Text(
            v,
            style: bold ? value.copyWith(fontWeight: FontWeight.bold) : value,
          ),
        ],
      );
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Bill Summary', style: title),
          const SizedBox(height: 12),
          billRow('Items Price', 'PKR ${itemsPrice.round()}'),
          if (isDelivery) ...[
            const SizedBox(height: 8),
            billRow('Delivery Fee', feeLabel),
          ],
          if (isDineIn) ...[
            const SizedBox(height: 8),
            billRow('Service Charges', serviceChargeLabel),
          ],
          const SizedBox(height: 8),
          billRow('Tax', taxLabel),
          const SizedBox(height: 12),
          const Divider(height: 1, color: Color(0xFFEEEEEE)),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: TextStyle(
                  fontSize: totalSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.textPrimary,
                ),
              ),
              FlameText(
                'PKR ${grandTotal.round()}',
                style: TextStyle(
                  fontSize: totalSize,
                  fontWeight: FontWeight.bold,
                  color: AppColors.matteBlack,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildItemCard(BuildContext context, OrderItem item) {
    final itemPrice = _parsePrice(item.price) * item.quantity;
    final variation = (item.selectedVariation ?? '').trim();
    final dealChoices = item.selectedDealOptions
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .where((e) {
          final lower = e.toLowerCase();
          return lower != 'regular' && lower != 'standard';
        })
        .toList();
    final isDeal = dealChoices.isNotEmpty;
    final showVariation = !isDeal &&
        variation.isNotEmpty &&
        variation.toLowerCase() != 'regular' &&
        variation.toLowerCase() != 'standard';
    final nameSize = ResponsiveHelper.isWide(context) ? 15.5 : 14.5;
    final detailSize = ResponsiveHelper.isWide(context) ? 12.5 : 11.5;
    final priceSize = ResponsiveHelper.isWide(context) ? 15.5 : 14.5;

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: item.imagePath.isNotEmpty
                ? ProductImageContainer(
                    imagePath: item.imagePath,
                    width: 76,
                    height: 76,
                    imageSize: 76,
                    borderRadius: 6,
                    backgroundColor: AppColors.surfaceElevated,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 76,
                    height: 76,
                    color: AppColors.surfaceElevated,
                    child: const Icon(
                      Icons.fastfood_outlined,
                      color: AppColors.textSecondary,
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.name,
                        style: TextStyle(
                          fontSize: nameSize,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (item.quantity > 1) ...[
                      const SizedBox(width: 6),
                      Text(
                        '×${item.quantity}',
                        style: TextStyle(
                          fontSize: nameSize - 1,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ],
                ),
                if (showVariation) ...[
                  const SizedBox(height: 2),
                  Text(
                    '•  $variation',
                    style: TextStyle(
                      fontSize: detailSize,
                      color: AppColors.textSecondary,
                      height: 1.25,
                    ),
                  ),
                ],
                if (dealChoices.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  ...dealChoices.map(
                    (opt) => Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        '•  $opt',
                        style: TextStyle(
                          fontSize: detailSize,
                          color: AppColors.textSecondary,
                          height: 1.25,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 8),
          FlameText(
            'PKR $itemPrice',
            style: TextStyle(
              fontSize: priceSize,
              fontWeight: FontWeight.bold,
              color: AppColors.matteBlack,
            ),
          ),
        ],
      ),
    );
  }
}
