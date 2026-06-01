import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:async';

class DriverScreen extends StatefulWidget {
  const DriverScreen({super.key});

  @override
  State<DriverScreen> createState() => _DriverScreenState();
}

class _DriverScreenState extends State<DriverScreen>
    with TickerProviderStateMixin {
  final client = Supabase.instance.client;
  List<Map<String, dynamic>> pendingOrders = [];
  String? activeOrderId;
  String orderStatus = 'waiting'; // waiting, active, completed
  RealtimeChannel? _channel;
  StreamSubscription<Position>? _positionStream;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      duration: const Duration(seconds: 2),
      vsync: this,
    )..repeat();
    _listenToOrders();
  }

  void _listenToOrders() {
    _channel = client.channel('pending-orders')
      ..onPostgresChanges(
        event: PostgresChangeEvent.insert,
        schema: 'public',
        table: 'orders',
        callback: (payload) {
          final order = payload.newRecord;
          if (order['status'] == 'pending') {
            setState(() => pendingOrders.add(order));
          }
        },
      )
      ..subscribe();

    _fetchPendingOrders();
  }

  Future<void> _fetchPendingOrders() async {
    final res = await client.from('orders').select().eq('status', 'pending');
    setState(() => pendingOrders = List<Map<String, dynamic>>.from(res));
  }

  Future<void> acceptOrder(Map<String, dynamic> order) async {
    final myId = client.auth.currentUser!.id;

    await client
        .from('orders')
        .update({'status': 'accepted', 'driver_id': myId})
        .eq('id', order['id']);

    setState(() {
      activeOrderId = order['id'];
      orderStatus = 'active';
      pendingOrders.remove(order);
    });

    _startSendingLocation(order['pickup_lat'], order['pickup_lng']);
  }

  void _startSendingLocation(double destLat, double destLng) async {
    await Geolocator.requestPermission();

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            distanceFilter: 5,
          ),
        ).listen((pos) async {
          final myId = client.auth.currentUser!.id;

          await client.from('driver_locations').upsert({
            'driver_id': myId,
            'lat': pos.latitude,
            'lng': pos.longitude,
            'updated_at': DateTime.now().toIso8601String(),
          });
        });
  }

  Future<void> openNavigation(double lat, double lng) async {
    final url = 'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng';
    await launchUrl(Uri.parse(url));
  }

  Future<void> completeOrder() async {
    await client
        .from('orders')
        .update({'status': 'completed'})
        .eq('id', activeOrderId!);

    _positionStream?.cancel();
    setState(() {
      activeOrderId = null;
      orderStatus = 'waiting';
    });
    _fetchPendingOrders();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _positionStream?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('لوحة السائق'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              final navigator = Navigator.of(context);
              await client.auth.signOut();
              if (!mounted) return;
              navigator.pushReplacementNamed('/');
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [const Color(0xff81E8AF).withAlpha(13), Colors.white],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: orderStatus == 'waiting' ? _buildWaiting() : _buildActive(),
        ),
      ),
    );
  }

  Widget _buildWaiting() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Status indicator
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.green.shade400, Colors.green.shade600],
            ),
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withAlpha((0.3 * 255).round()),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              ScaleTransition(
                scale: Tween(begin: 1.0, end: 1.2).animate(_pulseController),
                child: Container(
                  width: 12,
                  height: 12,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Text(
                'أنت متصل — في وضع الاستعداد',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'الطلبات المتاحة',
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: const Color(0xff81E8AF),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${pendingOrders.length}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        if (pendingOrders.isEmpty)
          Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      Icons.inbox_rounded,
                      size: 60,
                      color: Colors.grey.shade400,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'لا توجد طلبات حالياً',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: Colors.grey.shade600,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'سيتم إشعارك عند وصول طلب جديد',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Colors.grey.shade500,
                    ),
                  ),
                ],
              ),
            ),
          )
        else
          Expanded(
            child: RefreshIndicator(
              onRefresh: _fetchPendingOrders,
              child: ListView.builder(
                itemCount: pendingOrders.length,
                itemBuilder: (context, i) {
                  final order = pendingOrders[i];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Card(
                      elevation: 0,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(16),
                          gradient: LinearGradient(
                            colors: [Colors.white, Colors.blue.shade50],
                          ),
                          border: Border.all(
                            color: Colors.blue.shade100,
                            width: 1,
                          ),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Header
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      color: Colors.blue.shade100,
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Icon(
                                      Icons.local_shipping_rounded,
                                      color: const Color(0xff81E8AF),
                                      size: 20,
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'طلب جديد',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.labelSmall,
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          'رقم #${order['id'].toString().substring(0, 8)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.shade100,
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    child: Text(
                                      'قيد الانتظار',
                                      style: Theme.of(context)
                                          .textTheme
                                          .labelSmall
                                          ?.copyWith(
                                            color: Colors.amber.shade700,
                                            fontWeight: FontWeight.w600,
                                          ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Locations
                              Row(
                                children: [
                                  Column(
                                    children: [
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.green.shade500,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      Container(
                                        width: 2,
                                        height: 24,
                                        color: Colors.grey.shade300,
                                      ),
                                      Container(
                                        width: 12,
                                        height: 12,
                                        decoration: BoxDecoration(
                                          color: Colors.red.shade500,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'نقطة الاستلام',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.grey.shade600,
                                              ),
                                        ),
                                        Text(
                                          '${order['pickup_lat']?.toStringAsFixed(4)}, ${order['pickup_lng']?.toStringAsFixed(4)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          'نقطة التوصيل',
                                          style: Theme.of(context)
                                              .textTheme
                                              .labelSmall
                                              ?.copyWith(
                                                color: Colors.grey.shade600,
                                              ),
                                        ),
                                        Text(
                                          '${order['dest_lat']?.toStringAsFixed(4)}, ${order['dest_lng']?.toStringAsFixed(4)}',
                                          style: Theme.of(
                                            context,
                                          ).textTheme.bodySmall,
                                        ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              // Accept button
                              SizedBox(
                                width: double.infinity,
                                child: ElevatedButton.icon(
                                  onPressed: () => acceptOrder(order),
                                  icon: const Icon(Icons.check_circle_rounded),
                                  label: const Text('قبول الطلب'),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.green.shade500,
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 12,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildActive() {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [const Color(0xFF42A5F5), Colors.blue.shade600],
            ),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.blue.withAlpha((0.4 * 255).round()),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: const Icon(
            Icons.navigation_rounded,
            size: 60,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 28),
        Text(
          'أنت في رحلة نشطة!',
          style: Theme.of(
            context,
          ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'موقعك يُرسل للعميل تلقائياً 📡',
          style: Theme.of(
            context,
          ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 40),
        // Action buttons
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: () async {
              final order = await client
                  .from('orders')
                  .select()
                  .eq('id', activeOrderId!)
                  .single();
              openNavigation(order['pickup_lat'], order['pickup_lng']);
            },
            icon: const Icon(Icons.map_rounded),
            label: const Text('افتح Google Maps'),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF6366F1),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
          ),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 56,
          child: ElevatedButton.icon(
            onPressed: completeOrder,
            icon: const Icon(Icons.check_circle_rounded),
            label: const Text('تم التوصيل'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green.shade500,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              elevation: 4,
            ),
          ),
        ),
      ],
    );
  }
}
