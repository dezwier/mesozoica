// Typed parsers for the tool_actions YAML document.

import 'config_parsing.dart';
import 'field_survey_config.dart';
import 'tool_actions_mapping.dart';
import 'tool_actions_navigation.dart';
import 'tool_actions_sensing.dart';

export 'tool_actions_mapping.dart';
export 'tool_actions_navigation.dart';
export 'tool_actions_sensing.dart';

class ToolActionsConfig {
  const ToolActionsConfig({
    required this.aerialRecon,
    required this.aerialScout,
    required this.geoCompass,
    required this.proximityScanner,
    required this.siteNavigator,
    required this.orbitSurvey,
    required this.formationMap,
    required this.terrainEcho,
    required this.ridgeGlass,
    required this.trailStriders,
    required this.expeditionDrivetrain,
    required this.canyonThrottle,
    required this.overlandChassis,
    required this.nocturneLens,
    required this.brushScrim,
    required this.blackoutCover,
  });

  final AerialActionConfig aerialRecon;
  final AerialActionConfig aerialScout;
  final GuidanceActionConfig geoCompass;
  final GuidanceActionConfig proximityScanner;
  final GuidanceActionConfig siteNavigator;
  final OrbitSurveyActionConfig orbitSurvey;
  final FormationMapActionConfig formationMap;
  final TerrainEchoActionConfig terrainEcho;
  final MainParamBuffActionConfig ridgeGlass;
  final MainParamBuffActionConfig trailStriders;
  final MainParamBuffActionConfig expeditionDrivetrain;
  final MainParamBuffActionConfig canyonThrottle;
  final MainParamBuffActionConfig overlandChassis;
  final MainParamBuffActionConfig nocturneLens;
  final DisguiseActionConfig brushScrim;
  final DisguiseActionConfig blackoutCover;

  AerialActionConfig configFor(String actionKey) {
    switch (actionKey) {
      case 'aerial_scout':
        return aerialScout;
      case 'aerial_recon':
      default:
        return aerialRecon;
    }
  }

  GuidanceActionConfig guidanceConfigFor(String actionKey) {
    switch (actionKey) {
      case 'proximity_scanner':
        return proximityScanner;
      case 'site_navigator':
        return siteNavigator;
      case 'geo_compass':
      default:
        return geoCompass;
    }
  }

  DisguiseActionConfig disguiseConfigFor(String actionKey) {
    switch (actionKey) {
      case 'blackout_cover':
        return blackoutCover;
      case 'brush_scrim':
      default:
        return brushScrim;
    }
  }

  MainParamBuffActionConfig mainParamBuffConfigFor(String actionKey) {
    switch (actionKey) {
      case 'trail_striders':
        return trailStriders;
      case 'expedition_drivetrain':
        return expeditionDrivetrain;
      case 'canyon_throttle':
        return canyonThrottle;
      case 'overland_chassis':
        return overlandChassis;
      case 'nocturne_lens':
        return nocturneLens;
      case 'ridge_glass':
      default:
        return ridgeGlass;
    }
  }

  /// YAML / game-config defaults keyed like API `params` / `base_params`.
  Map<String, dynamic> defaultsForToolName(String name) {
    switch (name) {
      case 'Aerial Recon':
        return aerialRecon.toParamsJson();
      case 'Aerial Scout':
        return aerialScout.toParamsJson();
      case 'Geo Compass':
        return geoCompass.toParamsJson(actionKey: 'geo_compass');
      case 'Proximity Scanner':
        return proximityScanner.toParamsJson(actionKey: 'proximity_scanner');
      case 'Site Navigator':
        return siteNavigator.toParamsJson(actionKey: 'site_navigator');
      case 'Orbit Survey':
        return orbitSurvey.toParamsJson();
      case 'Formation Map':
        return formationMap.toParamsJson();
      case 'Terrain Echo':
        return terrainEcho.toParamsJson();
      case 'Ridge Glass':
        return ridgeGlass.toParamsJson();
      case 'Trail Striders':
        return trailStriders.toParamsJson();
      case 'Expedition Drivetrain':
        return expeditionDrivetrain.toParamsJson();
      case 'Canyon Throttle':
        return canyonThrottle.toParamsJson();
      case 'Overland Chassis':
        return overlandChassis.toParamsJson();
      case 'Nocturne Lens':
        return nocturneLens.toParamsJson();
      case 'Brush Scrim':
        return brushScrim.toParamsJson();
      case 'Blackout Cover':
        return blackoutCover.toParamsJson();
      default:
        return const {};
    }
  }

  factory ToolActionsConfig.fromYaml(Map<String, dynamic> yaml) {
    return ToolActionsConfig(
      aerialRecon: AerialActionConfig.fromYaml(
        configAsMap(yaml['aerial_recon']),
      ),
      aerialScout: AerialActionConfig.fromYaml(
        configAsMap(yaml['aerial_scout']),
        defaults: const AerialActionConfig(
          durationMinutes: 10,
          loopEndpointToleranceM: 75.0,
          flightSpeedKmh: 35.0,
          flightDiscoveryChance: 0.008,
          flightDiscoveryDistanceM: 50.0,
          ensureTimeoutS: 600,
          shortRouteWarnFraction: 0.7,
          statsExplanation:
              'Duration is this card\'s lifetime battery. Remaining time caps how far '
              'you can draw (speed × remaining). Flight time is drawn length ÷ speed. '
              'Sites within flight discovery distance are rolled at the listed chance.',
        ),
      ),
      geoCompass: GuidanceActionConfig.fromYaml(
        configAsMap(yaml['geo_compass']),
        defaults: GuidanceActionConfig(
          durationMinutes: 15,
          exactness: 0.0,
          modifiesMainParams: const ModifiesMainParams(
            using: {
              'field_survey': {
                'discovery_chance': ParamModifier(op: 'replace', value: 0.9),
              },
            },
          ),
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation:
              'Shows a direction range toward the nearest undiscovered site; '
              'lower exactness widens the glow.',
        ),
      ),
      proximityScanner: GuidanceActionConfig.fromYaml(
        configAsMap(yaml['proximity_scanner']),
        defaults: const GuidanceActionConfig(
          durationMinutes: 15,
          exactness: 0.0,
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation:
              'Shows distance to the nearest undiscovered site as meter bands.',
        ),
      ),
      siteNavigator: GuidanceActionConfig.fromYaml(
        configAsMap(yaml['site_navigator']),
        defaults: GuidanceActionConfig(
          durationMinutes: 15,
          directionExactness: 0.0,
          distanceExactness: 0.0,
          modifiesMainParams: const ModifiesMainParams(
            using: {
              'field_survey': {
                'discovery_chance': ParamModifier(op: 'replace', value: 0.9),
              },
            },
          ),
          directionHintPeriodS: 3.0,
          maxDirectionRangeDeg: 180.0,
          minDirectionRangeDeg: 4.0,
          statsExplanation:
              'Combines a direction-range glow and distance bands for the '
              'nearest undiscovered site.',
        ),
      ),
      orbitSurvey: OrbitSurveyActionConfig.fromYaml(
        configAsMap(yaml['orbit_survey']),
      ),
      formationMap: FormationMapActionConfig.fromYaml(
        configAsMap(yaml['formation_map']),
      ),
      terrainEcho: TerrainEchoActionConfig.fromYaml(
        configAsMap(yaml['terrain_echo']),
      ),
      ridgeGlass: MainParamBuffActionConfig.fromYaml(
        configAsMap(yaml['ridge_glass']),
      ),
      trailStriders: MainParamBuffActionConfig.fromYaml(
        configAsMap(yaml['trail_striders']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'documentation_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 0.95,
                ),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 100% so a fast jog '
              'still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 5%.',
        ),
      ),
      expeditionDrivetrain: MainParamBuffActionConfig.fromYaml(
        configAsMap(yaml['expedition_drivetrain']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'documentation_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 0.9,
                ),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 200% so bicycle '
              'travel still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 10%.',
        ),
      ),
      canyonThrottle: MainParamBuffActionConfig.fromYaml(
        configAsMap(yaml['canyon_throttle']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'documentation_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 0.85,
                ),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 300% so motorcycle '
              'travel still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 15%.',
        ),
      ),
      overlandChassis: MainParamBuffActionConfig.fromYaml(
        configAsMap(yaml['overland_chassis']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'documentation_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 0.8,
                ),
              },
            },
          ),
          statsExplanation:
              'While active, raises max discovery speed by 400% so 4x4 travel '
              'still counts toward discovery distance, but discover '
              'visibility, walk-in chance, and site exploration radius drop 20%.',
        ),
      ),
      nocturneLens: MainParamBuffActionConfig.fromYaml(
        configAsMap(yaml['nocturne_lens']),
        defaults: const MainParamBuffActionConfig(
          durationMinutes: 60,
          activeWeatherTimes: ['night'],
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'discovery_distance_m': ParamModifier(
                  op: 'multiply',
                  value: 1.4,
                ),
                'discovery_chance': ParamModifier(op: 'multiply', value: 1.4),
              },
            },
          ),
          statsExplanation:
              'Lifetime battery; only starts and runs at night. Boosts '
              'visibility range and walk-in discovery chance by 40%.',
        ),
      ),
      brushScrim: DisguiseActionConfig.fromYaml(
        configAsMap(yaml['brush_scrim']),
        defaults: const DisguiseActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'rival_discovery_chance': ParamModifier(
                  op: 'multiply',
                  value: 0,
                ),
              },
            },
          ),
          statsExplanation:
              'Covers one discovered site; multiplies rival_discovery_chance by 0. '
              'Successful site disguise XP only when a rival would have '
              'discovered the site without the cover.',
        ),
      ),
      blackoutCover: DisguiseActionConfig.fromYaml(
        configAsMap(yaml['blackout_cover']),
        defaults: const DisguiseActionConfig(
          durationMinutes: 60,
          modifiesMainParams: ModifiesMainParams(
            using: {
              'field_survey': {
                'rival_discovery_chance': ParamModifier(
                  op: 'multiply',
                  value: 0.5,
                ),
              },
            },
          ),
          statsExplanation:
              'Covers one discovered site; multiplies rival_discovery_chance by 0.5. '
              'Successful site disguise XP only when a rival would have '
              'discovered the site without the cover but the cover stops them.',
        ),
      ),
    );
  }
}
