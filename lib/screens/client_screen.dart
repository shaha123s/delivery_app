import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:geolocator/geolocator.dart';

class ClientScreen extends StatefulWidget {
  const ClientScreen({super.key});

  @override
  State<ClientScreen> createState() => _ClientScreenState();
}

class _ClientScreenState extends State<ClientScreen>
    with TickerProviderStateMixin {
  final client = Supabase.instance.client;
  String orderStatus = 'idle'; // idle, pending, accepted, completed
  String? orderId;
  String driverName = '';
  double? driverLat, driverLng;
  double? myLat, myLng;
  RealtimeChannel? _channel;
  late AnimationController _scaleController;

  @override
  void initState() {
    super.initState();
    _scaleController = AnimationController(
      duration: const Duration(seconds: 1),
      vsync: this,
    )..repeat(reverse: true);
    _getLocation();
  }

  Future<void> _getLocation() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.deniedForever) {
      await Geolocator.openAppSettings();
      return;
    }
    final pos = await Geolocator.getCurrentPosition();
    setState(() {
      myLat = pos.latitude;
      myLng = pos.longitude;
    });
  }

  Future<void> placeOrder() async {
    if (myLat == null) return;
    setState(() => orderStatus = 'pending');

    final res = await client
        .from('orders')
        .insert({
          'client_id': client.auth.currentUser!.id,
          'status': 'pending',
          'pickup_lat': myLat,
          'pickup_lng': myLng,
          'dest_lat': myLat! + 0.01,
          'dest_lng': myLng! + 0.01,
        })
        .select()
        .single();

    orderId = res['id'];
    _listenToOrder(orderId!);
  }

  void _listenToOrder(String id) {
    _channel = client.channel('order-$id')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'orders',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'id',
          value: id,
        ),
        callback: (payload) async {
          final data = payload.newRecord;
          if (data['status'] == 'accepted') {
            final driver = await client
                .from('users')
                .select('name')
                .eq('id', data['driver_id'])
                .single();
            setState(() {
              orderStatus = 'accepted';
              driverName = driver['name'];
            });
            _listenToDriverLocation(data['driver_id']);
          } else if (data['status'] == 'completed') {
            setState(() => orderStatus = 'completed');
            _channel?.unsubscribe();
          }
        },
      )
      ..subscribe();
  }

  void _listenToDriverLocation(String driverId) {
    client.channel('driver-loc-$driverId')
      ..onPostgresChanges(
        event: PostgresChangeEvent.update,
        schema: 'public',
        table: 'driver_locations',
        filter: PostgresChangeFilter(
          type: PostgresChangeFilterType.eq,
          column: 'driver_id',
          value: driverId,
        ),
        callback: (payload) {
          final data = payload.newRecord;
          setState(() {
            driverLat = data['lat'];
            driverLng = data['lng'];
          });
        },
      )
      ..subscribe();
  }

  double _calcDistance() {
    if (driverLat == null || myLat == null) return 0;
    return Geolocator.distanceBetween(driverLat!, driverLng!, myLat!, myLng!) /
        1000;
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _scaleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('عميل التوصيل'),
        centerTitle: true,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () async {
              await client.auth.signOut();
              if (mounted) Navigator.pushReplacementNamed(context, '/');
            },
          ),
        ],
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              const Color.fromARGB(255, 118, 216, 142).withOpacity(0.05),
              Colors.white,
            ],
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 118, 216, 142),
                      const Color.fromARGB(255, 118, 216, 142),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromARGB(
                        255,
                        118,
                        216,
                        142,
                      ).withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        myLat == null
                            ? 'جاري تحديد موقعك...'
                            : 'تم تحديد موقعك ✓',
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (myLat != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: const Icon(
                          Icons.check_circle_rounded,
                          color: Colors.white,
                          size: 16,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              Expanded(child: _buildContent()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildContent() {
    switch (orderStatus) {
      case 'idle':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween(begin: 1.0, end: 1.1).animate(_scaleController),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      const Color.fromARGB(255, 118, 216, 142),
                      const Color.fromARGB(255, 118, 216, 142),
                    ],
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: const Color.fromARGB(
                        255,
                        118,
                        216,
                        142,
                      ).withOpacity(0.4),
                      blurRadius: 20,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.local_shipping_rounded,
                  size: 60,
                  color: Colors.white,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'اطلب التوصيل الآن',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'اضغط الزر أدناه للبدء في رحلتك',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 40),
            SizedBox(
              width: double.infinity,
              height: 56,
              child: ElevatedButton.icon(
                onPressed: myLat == null ? null : placeOrder,
                icon: const Icon(Icons.send_rounded),
                label: const Text('🚀 اطلب الآن'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color.fromARGB(255, 99, 102, 241),
                  disabledBackgroundColor: Colors.grey.shade300,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                ),
              ),
            ),
          ],
        );

      case 'pending':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ScaleTransition(
                  scale: Tween(begin: 0.8, end: 1.2).animate(_scaleController),
                  child: Container(
                    width: 100,
                    height: 100,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF6366F1),
                        width: 3,
                      ),
                    ),
                  ),
                ),
                const Icon(
                  Icons.search_rounded,
                  size: 40,
                  color: Color(0xFF6366F1),
                ),
              ],
            ),
            const SizedBox(height: 28),
            Text(
              'جاري البحث عن سائق...',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'سيتم إخطارك قريباً',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _buildDot(0),
                const SizedBox(width: 8),
                _buildDot(1),
                const SizedBox(width: 8),
                _buildDot(2),
              ],
            ),
          ],
        );

      case 'accepted':
        final distance = _calcDistance();
        final minutes = (distance / 0.5).round();
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    const Color.fromARGB(255, 118, 216, 142),
                    const Color.fromARGB(255, 118, 216, 142),
                  ],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(
                      255,
                      118,
                      216,
                      142,
                    ).withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.directions_car_rounded,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              driverName,
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'السائق في الطريق إليك',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 28),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.grey.shade200, width: 1),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.straighten_rounded,
                          color: Colors.green.shade600,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${distance.toStringAsFixed(1)} كم',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'المسافة',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                  Container(width: 1, height: 80, color: Colors.grey.shade200),
                  Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(
                          Icons.timer_rounded,
                          color: Colors.orange.shade600,
                          size: 20,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '$minutes دقيقة',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'الوقت المتوقع',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.grey.shade600,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );

      case 'completed':
        return Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.green.shade400, Colors.green.shade600],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: const Color.fromARGB(
                      255,
                      118,
                      216,
                      142,
                    ).withOpacity(0.4),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                size: 60,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 28),
            Text(
              'تم التوصيل! ✓',
              style: Theme.of(
                context,
              ).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            Text(
              'شكراً لاستخدامك تطبيقنا',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade600),
            ),
          ],
        );

      default:
        return const SizedBox();
    }
  }

  Widget _buildDot(int index) {
    return ScaleTransition(
      scale: Tween(begin: 0.6, end: 1.0).animate(
        CurvedAnimation(
          parent: _scaleController,
          curve: Interval(
            index * 0.3,
            (index + 1) * 0.3,
            curve: Curves.easeInOut,
          ),
        ),
      ),
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: const Color.fromARGB(255, 118, 216, 142),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
