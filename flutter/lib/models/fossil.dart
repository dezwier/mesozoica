import '../utils/display_text.dart';
import '../utils/period_for_ages.dart';

class FossilStoredField {
  const FossilStoredField({
    required this.label,
    required this.value,
    this.maxValueLines = 2,
  });

  final String label;
  final String value;
  final int maxValueLines;
}

class FossilSummary {
  const FossilSummary({
    required this.id,
    required this.dinosaurId,
    required this.dinosaurName,
    this.identifiedName,
    this.identifiedRank,
    this.acceptedName,
    this.acceptedNo,
    this.acceptedRank,
    this.acceptedAttr,
    this.genus,
    this.family,
    this.taxonOrder,
    this.taxonClass,
    this.phylum,
    this.latitude,
    this.longitude,
    this.countryCode,
    this.state,
    this.geogcomments,
    this.geogscale,
    this.geoplate,
    this.latlngBasis,
    this.latlngPrecision,
    this.paleolat,
    this.paleolng,
    this.paleomodel,
    this.paleoage,
    this.geologicalFormation,
    this.minAgeMa,
    this.maxAgeMa,
    this.earlyInterval,
    this.stratcomments,
    this.stratscale,
    this.lithdescript,
    this.lithology1,
    this.lithadj1,
    this.concentration,
    this.temporalResolution,
    this.collectionName,
    this.collectionAka,
    this.collectionNo,
    this.collectionDates,
    this.collectionType,
    this.collectionMethods,
    this.collectors,
    this.museum,
    this.researchGroup,
    this.occurrenceComments,
    this.composition,
    this.architecture,
    this.fragmentation,
    this.presMode,
    this.preservationQuality,
    this.abundValue,
    this.abundUnit,
    this.fossilsfrom1,
    this.sizeClasses,
    this.recordType,
    this.articulatedParts,
    this.associatedParts,
    this.commonBodyParts,
    this.rareBodyParts,
    this.feedPredTraces,
    this.artifacts,
    this.componentComments,
    this.diet,
    this.environment,
    this.taxonEnvironment,
    this.lifeHabit,
    this.motility,
    this.reproduction,
    this.ontogeny,
    this.referenceNo,
    this.refAuthor,
    this.refPubyear,
    this.reidNo,
    this.description,
    this.mainImageUrl,
    this.llmRockType,
    this.llmCategory,
    this.llmSubcategory,
    this.llmPreservationQuality,
    this.llmCompleteness,
    this.llmDescription,
    this.llmImpRockType,
    this.llmImpCategory,
    this.llmImpSubcategory,
    this.llmImpPreservationQuality,
    this.llmImpCompleteness,
    this.dinosaurMainImageUrl,
    this.siteId,
    this.siteMainImageUrl,
  });

  final int id;
  final int dinosaurId;
  final String dinosaurName;
  final String? identifiedName;
  final String? identifiedRank;
  final String? acceptedName;
  final int? acceptedNo;
  final String? acceptedRank;
  final String? acceptedAttr;
  final String? genus;
  final String? family;
  final String? taxonOrder;
  final String? taxonClass;
  final String? phylum;
  final double? latitude;
  final double? longitude;
  final String? countryCode;
  final String? state;
  final String? geogcomments;
  final String? geogscale;
  final int? geoplate;
  final String? latlngBasis;
  final int? latlngPrecision;
  final double? paleolat;
  final double? paleolng;
  final String? paleomodel;
  final String? paleoage;
  final String? geologicalFormation;
  final double? minAgeMa;
  final double? maxAgeMa;
  final String? earlyInterval;
  final String? stratcomments;
  final String? stratscale;
  final String? lithdescript;
  final String? lithology1;
  final String? lithadj1;
  final String? concentration;
  final String? temporalResolution;
  final String? collectionName;
  final String? collectionAka;
  final int? collectionNo;
  final String? collectionDates;
  final String? collectionType;
  final String? collectionMethods;
  final String? collectors;
  final String? museum;
  final String? researchGroup;
  final String? occurrenceComments;
  final String? composition;
  final String? architecture;
  final String? fragmentation;
  final String? presMode;
  final String? preservationQuality;
  final int? abundValue;
  final String? abundUnit;
  final String? fossilsfrom1;
  final String? sizeClasses;
  final String? recordType;
  final String? articulatedParts;
  final String? associatedParts;
  final String? commonBodyParts;
  final String? rareBodyParts;
  final String? feedPredTraces;
  final String? artifacts;
  final String? componentComments;
  final String? diet;
  final String? environment;
  final String? taxonEnvironment;
  final String? lifeHabit;
  final String? motility;
  final String? reproduction;
  final String? ontogeny;
  final int? referenceNo;
  final String? refAuthor;
  final int? refPubyear;
  final int? reidNo;
  final String? description;
  final String? mainImageUrl;
  final String? llmRockType;
  final String? llmCategory;
  final String? llmSubcategory;
  final String? llmPreservationQuality;
  final String? llmCompleteness;
  final String? llmDescription;
  final String? llmImpRockType;
  final String? llmImpCategory;
  final String? llmImpSubcategory;
  final String? llmImpPreservationQuality;
  final String? llmImpCompleteness;
  final String? dinosaurMainImageUrl;
  final int? siteId;
  final String? siteMainImageUrl;

  factory FossilSummary.fromJson(Map<String, dynamic> json) {
    return FossilSummary(
      id: json['id'] as int,
      dinosaurId: json['dinosaur_id'] as int,
      dinosaurName: json['dinosaur_name'] as String,
      identifiedName: json['identified_name'] as String?,
      identifiedRank: json['identified_rank'] as String?,
      acceptedName: json['accepted_name'] as String?,
      acceptedNo: json['accepted_no'] as int?,
      acceptedRank: json['accepted_rank'] as String?,
      acceptedAttr: json['accepted_attr'] as String?,
      genus: json['genus'] as String?,
      family: json['family'] as String?,
      taxonOrder: json['taxon_order'] as String?,
      taxonClass: json['taxon_class'] as String?,
      phylum: json['phylum'] as String?,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      countryCode: json['country_code'] as String?,
      state: json['state'] as String?,
      geogcomments: json['geogcomments'] as String?,
      geogscale: json['geogscale'] as String?,
      geoplate: json['geoplate'] as int?,
      latlngBasis: json['latlng_basis'] as String?,
      latlngPrecision: json['latlng_precision'] as int?,
      paleolat: (json['paleolat'] as num?)?.toDouble(),
      paleolng: (json['paleolng'] as num?)?.toDouble(),
      paleomodel: json['paleomodel'] as String?,
      paleoage: json['paleoage'] as String?,
      geologicalFormation: json['geological_formation'] as String?,
      minAgeMa: (json['min_age_ma'] as num?)?.toDouble(),
      maxAgeMa: (json['max_age_ma'] as num?)?.toDouble(),
      earlyInterval: json['early_interval'] as String?,
      stratcomments: json['stratcomments'] as String?,
      stratscale: json['stratscale'] as String?,
      lithdescript: json['lithdescript'] as String?,
      lithology1: json['lithology1'] as String?,
      lithadj1: json['lithadj1'] as String?,
      concentration: json['concentration'] as String?,
      temporalResolution: json['temporal_resolution'] as String?,
      collectionName: json['collection_name'] as String?,
      collectionAka: json['collection_aka'] as String?,
      collectionNo: json['collection_no'] as int?,
      collectionDates: json['collection_dates'] as String?,
      collectionType: json['collection_type'] as String?,
      collectionMethods: json['collection_methods'] as String?,
      collectors: json['collectors'] as String?,
      museum: json['museum'] as String?,
      researchGroup: json['research_group'] as String?,
      occurrenceComments: json['occurrence_comments'] as String?,
      composition: json['composition'] as String?,
      architecture: json['architecture'] as String?,
      fragmentation: json['fragmentation'] as String?,
      presMode: json['pres_mode'] as String?,
      preservationQuality: json['preservation_quality'] as String?,
      abundValue: json['abund_value'] as int?,
      abundUnit: json['abund_unit'] as String?,
      fossilsfrom1: json['fossilsfrom1'] as String?,
      sizeClasses: json['size_classes'] as String?,
      recordType: json['record_type'] as String?,
      articulatedParts: json['articulated_parts'] as String?,
      associatedParts: json['associated_parts'] as String?,
      commonBodyParts: json['common_body_parts'] as String?,
      rareBodyParts: json['rare_body_parts'] as String?,
      feedPredTraces: json['feed_pred_traces'] as String?,
      artifacts: json['artifacts'] as String?,
      componentComments: json['component_comments'] as String?,
      diet: json['diet'] as String?,
      environment: json['environment'] as String?,
      taxonEnvironment: json['taxon_environment'] as String?,
      lifeHabit: json['life_habit'] as String?,
      motility: json['motility'] as String?,
      reproduction: json['reproduction'] as String?,
      ontogeny: json['ontogeny'] as String?,
      referenceNo: json['reference_no'] as int?,
      refAuthor: json['ref_author'] as String?,
      refPubyear: json['ref_pubyr'] as int?,
      reidNo: json['reid_no'] as int?,
      description: json['description'] as String?,
      mainImageUrl: json['main_image_url'] as String?,
      llmRockType: json['llm_rock_type'] as String?,
      llmCategory: json['llm_category'] as String?,
      llmSubcategory: json['llm_subcategory'] as String?,
      llmPreservationQuality: json['llm_preservation_quality'] as String?,
      llmCompleteness: json['llm_completeness'] as String?,
      llmDescription: json['llm_description'] as String?,
      llmImpRockType: json['llm_imp_rock_type'] as String?,
      llmImpCategory: json['llm_imp_category'] as String?,
      llmImpSubcategory: json['llm_imp_subcategory'] as String?,
      llmImpPreservationQuality: json['llm_imp_preservation_quality'] as String?,
      llmImpCompleteness: json['llm_imp_completeness'] as String?,
      dinosaurMainImageUrl: json['dinosaur_main_image_url'] as String?,
      siteId: json['site_id'] as int?,
      siteMainImageUrl: json['site_main_image_url'] as String?,
    );
  }

  String get displayTitle {
    final identified = identifiedName?.trim();
    if (identified != null && identified.isNotEmpty) {
      return displayTaxonName(identified);
    }
    return dinosaurName;
  }

  String get displayCoordinates {
    if (latitude == null || longitude == null) return '—';
    final lat = latitude!.toStringAsFixed(4);
    final lng = longitude!.toStringAsFixed(4);
    return '$lat, $lng';
  }

  String get displayRockType {
    final rock = lithology1?.trim();
    if (rock != null && rock.isNotEmpty) {
      return displayFactValue(rock);
    }
    final lith = lithdescript?.trim();
    if (lith != null && lith.isNotEmpty) {
      return displayFactValue(lith);
    }
    return displayFactValue(lithadj1);
  }

  String get displayPeriod {
    final interval = earlyInterval?.trim();
    final capitalizedInterval = interval != null && interval.isNotEmpty
        ? capitalizeLeadingLetter(interval)
        : null;
    final periodName = periodForAges(minAgeMa, maxAgeMa);
    final capitalizedPeriod = periodName != null && periodName.isNotEmpty
        ? capitalizeLeadingLetter(periodName)
        : null;

    if (minAgeMa != null && maxAgeMa != null) {
      final maLabel = minAgeMa!.round() == maxAgeMa!.round()
          ? '${minAgeMa!.round()} Ma'
          : '${minAgeMa!.round()} – ${maxAgeMa!.round()} Ma';
      if (capitalizedInterval != null) {
        return '$capitalizedInterval, $maLabel';
      }
      if (capitalizedPeriod != null) {
        return '$capitalizedPeriod, $maLabel';
      }
      return maLabel;
    }
    if (capitalizedInterval != null) {
      return capitalizedInterval;
    }
    if (capitalizedPeriod != null) {
      return capitalizedPeriod;
    }
    return '—';
  }

  String get displayCategory => displayFactValue(llmCategory);

  String get displaySubcategory => displayFactValue(llmSubcategory);

  String get displayPreservationQuality =>
      displayFactValue(llmPreservationQuality ?? preservationQuality);

  String get displayCompleteness => displayFactValue(llmCompleteness);

  String get displayImpCategory => displayFactValue(llmImpCategory);

  String get displayImpSubcategory => displayFactValue(llmImpSubcategory);

  String get displayImpPreservationQuality =>
      displayFactValue(llmImpPreservationQuality);

  String get displayImpCompleteness => displayFactValue(llmImpCompleteness);

  List<FossilStoredField> get storedFields {
    return [
      FossilStoredField(label: 'Occurrence no', value: '$id'),
      FossilStoredField(
        label: 'LLM description',
        value: displayFactValue(llmDescription),
        maxValueLines: 4,
      ),
      FossilStoredField(label: 'LLM category', value: displayFactValue(llmCategory)),
      FossilStoredField(
        label: 'LLM subcategory',
        value: displayFactValue(llmSubcategory),
      ),
      FossilStoredField(
        label: 'LLM preservation quality',
        value: displayFactValue(llmPreservationQuality),
      ),
      FossilStoredField(
        label: 'LLM completeness',
        value: displayFactValue(llmCompleteness),
      ),
      FossilStoredField(label: 'LLM rock type', value: displayFactValue(llmRockType)),
      FossilStoredField(label: 'Dinosaur', value: displayFactValue(dinosaurName)),
      FossilStoredField(
        label: 'Identified name',
        value: displayFactValue(identifiedName),
      ),
      FossilStoredField(
        label: 'Identified rank',
        value: displayFactValue(identifiedRank),
      ),
      FossilStoredField(
        label: 'Accepted name',
        value: displayFactValue(acceptedName),
      ),
      FossilStoredField(
        label: 'Accepted no',
        value: _displayInt(acceptedNo),
      ),
      FossilStoredField(
        label: 'Accepted rank',
        value: displayFactValue(acceptedRank),
      ),
      FossilStoredField(
        label: 'Accepted attr',
        value: displayFactValue(acceptedAttr),
      ),
      FossilStoredField(label: 'Genus', value: displayFactValue(genus)),
      FossilStoredField(label: 'Family', value: displayFactValue(family)),
      FossilStoredField(label: 'Taxon order', value: displayFactValue(taxonOrder)),
      FossilStoredField(label: 'Taxon class', value: displayFactValue(taxonClass)),
      FossilStoredField(label: 'Phylum', value: displayFactValue(phylum)),
      FossilStoredField(label: 'Country code', value: displayFactValue(countryCode)),
      FossilStoredField(label: 'State', value: displayFactValue(state)),
      FossilStoredField(
        label: 'Geography comments',
        value: displayFactValue(geogcomments),
        maxValueLines: 4,
      ),
      FossilStoredField(label: 'Geography scale', value: displayFactValue(geogscale)),
      FossilStoredField(label: 'Geoplate', value: _displayInt(geoplate)),
      FossilStoredField(label: 'Latlng basis', value: displayFactValue(latlngBasis)),
      FossilStoredField(
        label: 'Latlng precision',
        value: _displayInt(latlngPrecision),
      ),
      FossilStoredField(label: 'Latitude', value: _displayDecimal(latitude, decimals: 6)),
      FossilStoredField(label: 'Longitude', value: _displayDecimal(longitude, decimals: 6)),
      FossilStoredField(label: 'Paleolat', value: _displayDecimal(paleolat, decimals: 6)),
      FossilStoredField(label: 'Paleolng', value: _displayDecimal(paleolng, decimals: 6)),
      FossilStoredField(label: 'Paleomodel', value: displayFactValue(paleomodel)),
      FossilStoredField(label: 'Paleoage', value: displayFactValue(paleoage)),
      FossilStoredField(
        label: 'Geological formation',
        value: displayFactValue(geologicalFormation),
      ),
      FossilStoredField(label: 'Early interval', value: displayFactValue(earlyInterval)),
      FossilStoredField(label: 'Min age (Ma)', value: _displayDecimal(minAgeMa)),
      FossilStoredField(label: 'Max age (Ma)', value: _displayDecimal(maxAgeMa)),
      FossilStoredField(
        label: 'Stratigraphy comments',
        value: displayFactValue(stratcomments),
        maxValueLines: 4,
      ),
      FossilStoredField(label: 'Stratigraphy scale', value: displayFactValue(stratscale)),
      FossilStoredField(
        label: 'Lithology',
        value: displayFactValue(lithdescript),
        maxValueLines: 4,
      ),
      FossilStoredField(label: 'Lithology 1', value: displayFactValue(lithology1)),
      FossilStoredField(label: 'Lith adj 1', value: displayFactValue(lithadj1)),
      FossilStoredField(label: 'Concentration', value: displayFactValue(concentration)),
      FossilStoredField(
        label: 'Temporal resolution',
        value: displayFactValue(temporalResolution),
      ),
      FossilStoredField(label: 'Collection name', value: displayFactValue(collectionName)),
      FossilStoredField(label: 'Collection aka', value: displayFactValue(collectionAka)),
      FossilStoredField(label: 'Collection no', value: _displayInt(collectionNo)),
      FossilStoredField(label: 'Collection dates', value: displayFactValue(collectionDates)),
      FossilStoredField(label: 'Collection type', value: displayFactValue(collectionType)),
      FossilStoredField(
        label: 'Collection methods',
        value: displayFactValue(collectionMethods),
        maxValueLines: 3,
      ),
      FossilStoredField(
        label: 'Occurrence comments',
        value: displayFactValue(occurrenceComments),
        maxValueLines: 4,
      ),
      FossilStoredField(label: 'Composition', value: displayFactValue(composition)),
      FossilStoredField(label: 'Architecture', value: displayFactValue(architecture)),
      FossilStoredField(label: 'Fragmentation', value: displayFactValue(fragmentation)),
      FossilStoredField(
        label: 'Collectors',
        value: displayFactValue(collectors),
        maxValueLines: 3,
      ),
      FossilStoredField(label: 'Museum', value: displayFactValue(museum)),
      FossilStoredField(label: 'Research group', value: displayFactValue(researchGroup)),
      FossilStoredField(label: 'Preservation mode', value: displayFactValue(presMode)),
      FossilStoredField(
        label: 'Preservation quality',
        value: displayFactValue(preservationQuality),
      ),
      FossilStoredField(label: 'Abundance value', value: _displayInt(abundValue)),
      FossilStoredField(label: 'Abundance unit', value: displayFactValue(abundUnit)),
      FossilStoredField(label: 'Fossils from 1', value: displayFactValue(fossilsfrom1)),
      FossilStoredField(label: 'Size classes', value: displayFactValue(sizeClasses)),
      FossilStoredField(label: 'Record type', value: displayFactValue(recordType)),
      FossilStoredField(
        label: 'Common body parts',
        value: displayFactValue(commonBodyParts),
      ),
      FossilStoredField(
        label: 'Rare body parts',
        value: displayFactValue(rareBodyParts),
      ),
      FossilStoredField(
        label: 'Articulated parts',
        value: displayFactValue(articulatedParts),
      ),
      FossilStoredField(
        label: 'Associated parts',
        value: displayFactValue(associatedParts),
      ),
      FossilStoredField(
        label: 'Feed/pred traces',
        value: displayFactValue(feedPredTraces),
      ),
      FossilStoredField(label: 'Artifacts', value: displayFactValue(artifacts)),
      FossilStoredField(
        label: 'Component comments',
        value: displayFactValue(componentComments),
        maxValueLines: 4,
      ),
      FossilStoredField(label: 'Diet', value: displayFactValue(diet)),
      FossilStoredField(label: 'Environment', value: displayFactValue(environment)),
      FossilStoredField(
        label: 'Taxon environment',
        value: displayFactValue(taxonEnvironment),
      ),
      FossilStoredField(label: 'Life habit', value: displayFactValue(lifeHabit)),
      FossilStoredField(label: 'Motility', value: displayFactValue(motility)),
      FossilStoredField(label: 'Reproduction', value: displayFactValue(reproduction)),
      FossilStoredField(label: 'Ontogeny', value: displayFactValue(ontogeny)),
      FossilStoredField(label: 'Reference no', value: _displayInt(referenceNo)),
      FossilStoredField(label: 'Ref author', value: displayFactValue(refAuthor)),
      FossilStoredField(label: 'Ref pubyr', value: _displayInt(refPubyear)),
      FossilStoredField(label: 'Reid no', value: _displayInt(reidNo)),
      FossilStoredField(
        label: 'Description',
        value: displayFactValue(description),
        maxValueLines: 4,
      ),
    ];
  }
}

String _displayDecimal(double? value, {int decimals = 2}) {
  if (value == null) return '—';
  return value.toStringAsFixed(decimals);
}

String _displayInt(int? value) {
  if (value == null) return '—';
  return '$value';
}

class FossilListResponse {
  const FossilListResponse({
    required this.items,
    required this.total,
    required this.limit,
    required this.offset,
    required this.hasNext,
  });

  final List<FossilSummary> items;
  final int total;
  final int limit;
  final int offset;
  final bool hasNext;

  bool get hasMore => hasNext;

  factory FossilListResponse.fromJson(Map<String, dynamic> json) {
    final rawItems = json['items'] as List<dynamic>? ?? [];
    return FossilListResponse(
      items: rawItems
          .map((item) => FossilSummary.fromJson(item as Map<String, dynamic>))
          .toList(),
      total: json['total'] as int? ?? rawItems.length,
      limit: json['limit'] as int? ?? rawItems.length,
      offset: json['offset'] as int? ?? 0,
      hasNext: json['has_next'] as bool? ?? false,
    );
  }
}
