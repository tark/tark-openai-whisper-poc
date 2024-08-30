part of 'main_cubit.dart';

class MainState extends Equatable {
  const MainState({
    this.appVersion = '',
    this.apiUrl = '',
    this.showOnboarding = true,
  });

  const MainState.initial()
      : appVersion = '',
        apiUrl = '',
        showOnboarding = true;

  final String? appVersion;
  final String? apiUrl;
  final bool showOnboarding;

  MainState copyWith({
    String? appVersion,
    String? apiUrl,
    bool? showOnboarding,
  }) {
    return MainState(
      appVersion: appVersion ?? this.appVersion,
      apiUrl: apiUrl ?? this.apiUrl,
      showOnboarding: showOnboarding ?? this.showOnboarding,
    );
  }

  @override
  List<Object?> get props => [
    appVersion,
    apiUrl,
    showOnboarding,
  ];
}
