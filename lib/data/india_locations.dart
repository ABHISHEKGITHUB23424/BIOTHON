class IndiaLocation {
  final String name;
  final String state;
  final double latitude;
  final double longitude;

  const IndiaLocation({
    required this.name,
    required this.state,
    required this.latitude,
    required this.longitude,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is IndiaLocation &&
          runtimeType == other.runtimeType &&
          name == other.name;

  @override
  int get hashCode => name.hashCode;
}

const List<IndiaLocation> indiaLocations = [
  IndiaLocation(name: "Delhi NCR", state: "Delhi", latitude: 28.6139, longitude: 77.2090),
  IndiaLocation(name: "Mumbai MMR", state: "Maharashtra", latitude: 19.0760, longitude: 72.8777),
  IndiaLocation(name: "Bengaluru Urban", state: "Karnataka", latitude: 12.9716, longitude: 77.5946),
  IndiaLocation(name: "Chennai", state: "Tamil Nadu", latitude: 13.0827, longitude: 80.2707),
  IndiaLocation(name: "Hyderabad", state: "Telangana", latitude: 17.3850, longitude: 78.4867),
  IndiaLocation(name: "Ahmedabad", state: "Gujarat", latitude: 23.0225, longitude: 72.5714),
  IndiaLocation(name: "Kolkata", state: "West Bengal", latitude: 22.5726, longitude: 88.3639),
  IndiaLocation(name: "Pune", state: "Maharashtra", latitude: 18.5204, longitude: 73.8567),
  IndiaLocation(name: "Jaipur", state: "Rajasthan", latitude: 26.9124, longitude: 75.7873),
  IndiaLocation(name: "Lucknow", state: "Uttar Pradesh", latitude: 26.8467, longitude: 80.9462),
  IndiaLocation(name: "Kanpur", state: "Uttar Pradesh", latitude: 26.4499, longitude: 80.3319),
  IndiaLocation(name: "Nagpur", state: "Maharashtra", latitude: 21.1458, longitude: 79.0882),
  IndiaLocation(name: "Patna", state: "Bihar", latitude: 25.5941, longitude: 85.1376),
  IndiaLocation(name: "Indore", state: "Madhya Pradesh", latitude: 22.7196, longitude: 75.8577),
  IndiaLocation(name: "Bhopal", state: "Madhya Pradesh", latitude: 23.2599, longitude: 77.4126),
  IndiaLocation(name: "Visakhapatnam", state: "Andhra Pradesh", latitude: 17.6868, longitude: 83.2185),
  IndiaLocation(name: "Vadodara", state: "Gujarat", latitude: 22.3072, longitude: 73.1812),
  IndiaLocation(name: "Ludhiana", state: "Punjab", latitude: 30.9010, longitude: 75.8573),
  IndiaLocation(name: "Agra", state: "Uttar Pradesh", latitude: 27.1767, longitude: 78.0081),
  IndiaLocation(name: "Nashik", state: "Maharashtra", latitude: 19.9975, longitude: 73.7898),
  IndiaLocation(name: "Ranchi", state: "Jharkhand", latitude: 23.3441, longitude: 85.3096),
  IndiaLocation(name: "Faridabad", state: "Haryana", latitude: 28.4089, longitude: 77.3178),
  IndiaLocation(name: "Ghaziabad", state: "Uttar Pradesh", latitude: 28.6692, longitude: 77.4538),
  IndiaLocation(name: "Noida", state: "Uttar Pradesh", latitude: 28.5355, longitude: 77.3910),
  IndiaLocation(name: "Guwahati", state: "Assam", latitude: 26.1445, longitude: 91.7362),
  IndiaLocation(name: "Chandigarh", state: "Chandigarh", latitude: 30.7333, longitude: 76.7794),
  IndiaLocation(name: "Dehradun", state: "Uttarakhand", latitude: 30.3165, longitude: 78.0322),
  IndiaLocation(name: "Bhubaneswar", state: "Odisha", latitude: 20.2961, longitude: 85.8245),
  IndiaLocation(name: "Raipur", state: "Chhattisgarh", latitude: 21.2514, longitude: 81.6296),
  IndiaLocation(name: "Kochi", state: "Kerala", latitude: 9.9312, longitude: 76.2673),
  IndiaLocation(name: "Thiruvananthapuram", state: "Kerala", latitude: 8.5241, longitude: 76.9366),
  IndiaLocation(name: "Madurai", state: "Tamil Nadu", latitude: 9.9252, longitude: 78.1198),
  IndiaLocation(name: "Coimbatore", state: "Tamil Nadu", latitude: 11.0168, longitude: 76.9558),
  IndiaLocation(name: "Vijayawada", state: "Andhra Pradesh", latitude: 16.5062, longitude: 80.6480),
  IndiaLocation(name: "Shimla", state: "Himachal Pradesh", latitude: 31.1048, longitude: 77.1734),
  IndiaLocation(name: "Srinagar", state: "Jammu and Kashmir", latitude: 34.0837, longitude: 74.7973),
  IndiaLocation(name: "Panaji", state: "Goa", latitude: 15.4909, longitude: 73.8278),
  IndiaLocation(name: "Port Blair", state: "Andaman and Nicobar Islands", latitude: 11.6234, longitude: 92.7265),
  IndiaLocation(name: "Shillong", state: "Meghalaya", latitude: 25.5788, longitude: 91.8931),
  IndiaLocation(name: "Imphal", state: "Manipur", latitude: 24.8170, longitude: 93.9368),
];
