import 'package:flutter/material.dart';
import '../controllers/order_controller.dart';
import '../utils/app_colors.dart';
import '../widgets/custom_header.dart';
import '../widgets/flame_text.dart';
import '../widgets/shimmer.dart';
import '../widgets/product_image_container.dart';
import 'order_details_screen.dart';

class MyOrdersScreen extends StatefulWidget {
  /// When true, shown as a right-side overlay panel (desktop/laptop).
  final bool asSidePanel;

  const MyOrdersScreen({super.key, this.asSidePanel = false});

  @override
  State<MyOrdersScreen> createState() => _MyOrdersScreenState();
}

class _MyOrdersScreenState extends State<MyOrdersScreen> {
  final OrderController _orderController = OrderController();

  @override
  void initState() {
    super.initState();
    _orderController.addListener(_onOrdersChanged);
    _orderController.loadOrders();
  }

  @override
  void dispose() {
    _orderController.removeListener(_onOrdersChanged);
    super.dispose();
  }

  void _onOrdersChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _refreshOrders() async {
    await _orderController.loadOrders(showRefreshing: true);
  }

  @override
  Widget build(BuildContext context) {
    final orders = _orderController.orders;
    final isLoaded = _orderController.isLoaded;
    final isRefreshing = _orderController.isRefreshing;

    return Scaffold(
      backgroundColor: AppColors.matteBlack,
      appBar: CustomHeader(
        title: 'My Orders',
        subtitle: '',
        showBackButton: true,
        showCartIcon: false,
        onBackTap: widget.asSidePanel
            ? () => Navigator.of(context).maybePop()
            : null,
        onRefreshTap: isLoaded ? _refreshOrders : null,
        isRefreshing: isRefreshing,
      ),
      body: !isLoaded
          ? ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
              itemCount: 4,
              itemBuilder: (context, index) => const Padding(
                padding: EdgeInsets.only(bottom: 12.0),
                child: Shimmer.rectangular(width: double.infinity, height: 120),
              ),
            )
          : orders.isEmpty
          ? _buildEmptyState(context)
          : _buildOrderList(orders),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: AppColors.flameGradient,
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: AppColors.cardBackground,
                size: 32,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              "No Placed Orders Found",
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.bold,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            Text(
              "Looks like you haven't placed any orders yet.",
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13.5,
                color: AppColors.textSecondary,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOrderList(List<OrderModel> orders) {
    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 28, 12, 16),
      itemCount: orders.length,
      separatorBuilder: (context, index) => const SizedBox(height: 30),
      itemBuilder: (context, index) {
        return _buildOrderTile(orders[index]);
      },
    );
  }

  Widget _buildOrderTile(OrderModel order) {
    final firstItem = order.items.isNotEmpty ? order.items.first : null;
    final remainingCount = order.items.length > 1 ? order.items.length - 1 : 0;
    final showRider =
        order.status == 'Out for Delivery' &&
        (order.riderName.isNotEmpty || order.riderPhone.isNotEmpty);
    final normalizedStatus = order.status.trim().toLowerCase();
    // `Out for Delivery` contains the word "delivery", so we only treat
    // "delivered" as completed (not "delivery").
    final isCancelledStatus = normalizedStatus.contains('cancel');
    final isDeclinedStatus = normalizedStatus.contains('decline') ||
        normalizedStatus.contains('reject');
    final type = order.orderType.trim().toLowerCase();
    final isPickupFinal = (type.contains('pickup') || type.contains('takeaway')) &&
        (normalizedStatus == 'picked' || normalizedStatus.contains('picked'));
    final isDineInFinal = type.contains('dine') &&
        (normalizedStatus.contains('served') ||
            normalizedStatus.contains('completed'));
    final isDeliveryFinal =
        type.contains('delivery') && normalizedStatus.contains('delivered');
    // Same as delivery Cancelled: hide tracker, show status chip/container.
    final showFinalStatusBadge =
        isCancelledStatus ||
        isDeclinedStatus ||
        isPickupFinal ||
        isDineInFinal ||
        isDeliveryFinal;

    final itemTitle = firstItem?.name ?? 'Order';

    return Material(
      color: AppColors.cardBackground,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => OrderDetailsScreen(order: order)),
          );
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    order.orderId,
                    style: const TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.w700,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  Text(
                    order.orderType == 'Pickup'
                        ? 'Pickup'
                        : order.orderType == 'Dine In'
                        ? 'Dine In'
                        : 'Delivery',
                    style: const TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              showFinalStatusBadge
                  ? _buildFinalStatusBadge(order.status)
                  : _buildStatusTracker(
                      order.status,
                      order.orderType,
                    ),
              const SizedBox(height: 14),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text.rich(
                          TextSpan(
                            children: [
                              TextSpan(
                                text: itemTitle,
                                style: const TextStyle(
                                  fontSize: 16.5,
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.primary,
                                ),
                              ),
                              if (remainingCount > 0)
                                TextSpan(
                                  text: '  +$remainingCount more',
                                  style: TextStyle(
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w500,
                                    color: AppColors.textSecondary,
                                  ),
                                ),
                            ],
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_formatDate(order.orderDate)}  ${_formatTime(order.orderDate)}',
                          style: const TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w500,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        FlameText(
                          'Rs ${order.totalAmount.round()}',
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                            color: AppColors.matteBlack,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 80,
                    height: 80,
                    decoration: BoxDecoration(
                      color: AppColors.surfaceElevated,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: firstItem != null && firstItem.imagePath.isNotEmpty
                          ? ProductImageContainer(
                              imagePath: firstItem.imagePath,
                              width: 80,
                              height: 80,
                              imageSize: 80,
                              borderRadius: 6,
                              backgroundColor: AppColors.surfaceElevated,
                              fit: BoxFit.cover,
                            )
                          : const Icon(
                              Icons.fastfood_outlined,
                              color: AppColors.textSecondary,
                              size: 28,
                            ),
                    ),
                  ),
                ],
              ),
              if (showRider) ...[
                const SizedBox(height: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rider Name: ${order.riderName.isNotEmpty ? order.riderName : '-'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Rider Number: ${order.riderPhone.isNotEmpty ? order.riderPhone : '-'}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFinalStatusBadge(String status) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        gradient: AppColors.flameGradient,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Text(
        status,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.matteBlack,
        ),
      ),
    );
  }

  Widget _buildStatusTracker(String currentStatus, String orderType) {
    final statuses = OrderModel.statusStepsFor(orderType);
    final normalized = OrderModel.normalizeStatus(
      currentStatus,
      orderType: orderType,
    );
    var currentIndex = statuses.indexOf(normalized);
    if (currentIndex < 0) {
      final lower = normalized.toLowerCase();
      currentIndex = statuses.indexWhere(
        (s) => lower.contains(s.toLowerCase()) || s.toLowerCase().contains(lower),
      );
      if (currentIndex < 0) {
        // Fallback fuzzy match by last word (e.g. Preparing)
        currentIndex = statuses.indexWhere(
          (s) => lower.contains(s.toLowerCase().split(' ').last),
        );
      }
    }
    final activeIndex = currentIndex < 0 ? 0 : currentIndex;

    return Column(
      children: [
        SizedBox(
          height: 18,
          child: Stack(
            alignment: Alignment.center,
            children: [
              Positioned(
                left: 17,
                right: 17,
                child: Row(
                  children: List.generate(statuses.length - 1, (index) {
                    final isActive = index < activeIndex;
                    return Expanded(
                      child: Container(
                        height: 2,
                        decoration: BoxDecoration(
                          gradient: isActive ? AppColors.flameGradient : null,
                          color: isActive ? null : AppColors.border,
                        ),
                      ),
                    );
                  }),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: List.generate(statuses.length, (index) {
                    final isActive = index <= activeIndex;
                    return Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: isActive ? AppColors.flameGradient : null,
                        color: isActive ? null : AppColors.border,
                      ),
                      child: Icon(
                        isActive ? Icons.check_rounded : Icons.circle_outlined,
                        size: 12,
                        color: isActive
                            ? AppColors.onPrimary
                            : Colors.grey.shade500,
                      ),
                    );
                  }),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Transform.translate(
          offset: const Offset(4, 0),
          child: Row(
            children: List.generate(statuses.length, (index) {
              final isActive = index <= activeIndex;
              return Expanded(
                child: Text(
                  statuses[index],
                  style: TextStyle(
                    fontSize: statuses.length >= 4 ? 11.5 : 12,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w500,
                    color: AppColors.textPrimary,
                    height: 1.2,
                  ),
                  textAlign: index == 0
                      ? TextAlign.left
                      : index == statuses.length - 1
                      ? TextAlign.right
                      : TextAlign.center,
                  maxLines: 2,
                  softWrap: true,
                  overflow: TextOverflow.visible,
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
  }

  String _formatTime(DateTime date) {
    final hour = date.hour == 0
        ? 12
        : date.hour > 12
        ? date.hour - 12
        : date.hour;
    final minute = date.minute.toString().padLeft(2, '0');
    final period = date.hour < 12 ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }
}
