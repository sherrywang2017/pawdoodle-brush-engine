part of '../../held_stroke_assist.dart';

class PawStrokeAssistClassifier {
  const PawStrokeAssistClassifier();

  PawStrokeAssistClassification classify(
    List<DrawingInputSample> input, {
    required PawStrokeHoldAssistConfiguration configuration,
  }) =>
      rankCandidates(input, configuration: configuration).first;

  List<PawStrokeAssistClassification> rankCandidates(
    List<DrawingInputSample> input, {
    required PawStrokeHoldAssistConfiguration configuration,
  }) {
    final samples = _deduplicateSamples(
      input,
      configuration.minimumRecordedPointDistance,
    );
    if (samples.length < 2) {
      return const <PawStrokeAssistClassification>[
        PawStrokeAssistClassification(
          kind: PawStrokeAssistKind.freeformSmooth,
          confidence: 0,
        ),
      ];
    }
    final points = samples.map((sample) => sample.position).toList();
    final scale = _pointScale(points);
    final pathLength = _polylineLength(points);
    final chord = (points.last - points.first).distance;
    final closureTolerance = math.max(6.0, scale * .1);
    final closed = points.length >= 8 &&
        (points.last - points.first).distance <= closureTolerance &&
        pathLength >= math.max(24, scale * 2.1);
    final candidates = <PawStrokeAssistClassification>[
      const PawStrokeAssistClassification(
        kind: PawStrokeAssistKind.freeformSmooth,
        confidence: 0,
      ),
    ];

    final line = _orthogonalLineFit(points);
    final lineRmsTolerance = math.max(1.35, scale * .022);
    final lineMaxTolerance = math.max(2.8, scale * .052);
    final lineEfficiency = pathLength <= .001 ? 0 : chord / pathLength;
    if (!closed &&
        chord >= configuration.minimumMeaningfulPathLength &&
        line.rmsResidual <= lineRmsTolerance &&
        line.maximumResidual <= lineMaxTolerance &&
        lineEfficiency >= .84) {
      final confidence = _minimumConfidence(<double>[
        1 - line.rmsResidual / lineRmsTolerance,
        1 - line.maximumResidual / lineMaxTolerance,
        (lineEfficiency - .84) / .16,
      ]);
      if (confidence >= configuration.minimumLineConfidence) {
        candidates.add(PawStrokeAssistClassification(
          kind: PawStrokeAssistKind.line,
          confidence: confidence,
        ));
      }
    }

    // Circle/ellipse candidacy is based on sweep and fit quality, not a strict
    // endpoint closure branch. A 300-360 degree gesture can therefore win the
    // same ranked comparison while a shorter open arc remains an ARC.
    final fullCircle = points.length >= 8 ? _fitCircle(points) : null;
    if (fullCircle != null) {
      final circleClosure = _canonicalClosureTopology(
        points,
        pathLength: pathLength,
        scale: scale,
        signedSweep: fullCircle.signedSweep,
        perimeter: math.pi * 2 * fullCircle.radius,
      );
      final tolerance = math.max(2.2, scale * .045);
      if (circleClosure['passed'] == true &&
          fullCircle.signCoherence >= .78 &&
          fullCircle.signedSweep.abs() >= math.pi * 1.8 &&
          fullCircle.trimmedRmsResidual <= tolerance &&
          fullCircle.p90Residual <= tolerance * 1.8 &&
          fullCircle.maximumResidual <= tolerance * 4) {
        final confidence = _averageConfidence(<double>[
          1 - fullCircle.trimmedRmsResidual / (tolerance * 1.25),
          1 - fullCircle.p90Residual / (tolerance * 2),
          (fullCircle.signCoherence - .74) / .26,
          1 -
              (points.last - points.first).distance /
                  math.max(1, math.pi * 2 * fullCircle.radius * .24),
        ]);
        if (confidence >=
            configuration.minimumAcceptanceConfidenceFor(
              PawStrokeAssistKind.circle,
            )) {
          candidates.add(PawStrokeAssistClassification(
            kind: PawStrokeAssistKind.circle,
            confidence: confidence,
            ellipseFit: PawEllipseFit(
              center: fullCircle.center,
              majorRadius: fullCircle.radius,
              minorRadius: fullCircle.radius,
              rotationRadians: 0,
              rmsRadialResidual: fullCircle.rmsResidual / fullCircle.radius,
              maximumRadialResidual:
                  fullCircle.maximumResidual / fullCircle.radius,
              signedSweep: fullCircle.signedSweep,
              signCoherence: fullCircle.signCoherence,
            ),
            closureTopology: circleClosure,
          ));
        }
      }
    }
    final ellipse = points.length >= 8 ? _fitEllipse(points) : null;
    final ellipseClosure = ellipse == null
        ? const <String, Object>{}
        : _canonicalClosureTopology(
            points,
            pathLength: pathLength,
            scale: scale,
            signedSweep: ellipse.signedSweep,
            perimeter: math.pi *
                (3 * (ellipse.majorRadius + ellipse.minorRadius) -
                    math.sqrt((3 * ellipse.majorRadius + ellipse.minorRadius) *
                        (ellipse.majorRadius + 3 * ellipse.minorRadius))),
          );
    if (ellipse != null &&
        ellipseClosure['passed'] == true &&
        ellipse.signCoherence >= .72 &&
        ellipse.signedSweep.abs() >= math.pi * 1.55 &&
        ellipse.rmsRadialResidual <= .19 &&
        ellipse.maximumRadialResidual <= .46 &&
        ellipse.minorRadius >= math.max(4, scale * .08)) {
      final axisRatio = ellipse.minorRadius / ellipse.majorRadius;
      final kind = axisRatio >= .88
          ? PawStrokeAssistKind.circle
          : PawStrokeAssistKind.ellipse;
      final endpointGap = (points.last - points.first).distance;
      final perimeterScale = math.pi *
          (3 * (ellipse.majorRadius + ellipse.minorRadius) -
              math.sqrt((3 * ellipse.majorRadius + ellipse.minorRadius) *
                  (ellipse.majorRadius + 3 * ellipse.minorRadius)));
      // Once the gesture has one coherent sweep and passes the explicit
      // closure topology, do not let one locally flat or overshot sample veto
      // the user's closed-shape intent.  A weighted average still makes a
      // genuinely poor ellipse lose to a polygon or free curve, while the
      // physical iPhone trace with a short missing closing arc can become the
      // exact four-cubic ellipse Draw-and-Hold promises.
      final confidence = _averageConfidence(<double>[
        1 - ellipse.rmsRadialResidual / .19,
        1 - ellipse.maximumRadialResidual / .46,
        (ellipse.signCoherence - .7) / .3,
        ((ellipse.signedSweep.abs() / (math.pi * 2)) - .75) / .25,
        1 - endpointGap / math.max(1, perimeterScale * .28),
      ]);
      if (confidence >= configuration.minimumAcceptanceConfidenceFor(kind)) {
        candidates.add(PawStrokeAssistClassification(
          kind: kind,
          confidence: confidence,
          ellipseFit: ellipse,
          closureTopology: ellipseClosure,
        ));
      }
    }

    if (closed) {
      final polygon = _closedPolygonVertices(points, scale);
      if (polygon.length == 3 || polygon.length == 4) {
        final confidence = _closedPolylineConfidence(points, polygon, scale);
        final kind = polygon.length == 3
            ? PawStrokeAssistKind.triangle
            : PawStrokeAssistKind.quadrilateral;
        if (confidence >= configuration.minimumAcceptanceConfidenceFor(kind)) {
          candidates.add(PawStrokeAssistClassification(
            kind: kind,
            confidence: confidence,
            vertexIndices: List<int>.unmodifiable(polygon),
          ));
        }
      }
    }

    if (!closed) {
      final vertices = _openPolylineVertices(points, scale);
      if (vertices.length >= 3 && vertices.length <= 9) {
        final confidence = _openPolylineConfidence(points, vertices, scale);
        if (confidence >=
            configuration.minimumAcceptanceConfidenceFor(
              PawStrokeAssistKind.polyline,
            )) {
          candidates.add(PawStrokeAssistClassification(
            kind: PawStrokeAssistKind.polyline,
            confidence: confidence,
            vertexIndices: List<int>.unmodifiable(vertices),
          ));
        }
      }

      final circle = _fitCircle(points);
      // A held, single-turn curve is a request for a geometric arc rather
      // than for a merely smoother freehand cubic. Keep the fit robust to the
      // sparse 60 Hz touch intervals seen in physical captures, then emit the
      // accepted result from one circle so curvature is constant everywhere.
      final circleTolerance = math.max(2.0, scale * .034);
      if (circle != null &&
          circle.signCoherence >= .78 &&
          circle.signedSweep.abs() >= .35 &&
          circle.signedSweep.abs() < math.pi * 1.85 &&
          circle.trimmedRmsResidual <= circleTolerance &&
          circle.p90Residual <= circleTolerance * 2.0 &&
          circle.maximumResidual <= circleTolerance * 4.8) {
        final confidence = _minimumConfidence(<double>[
          1 - circle.trimmedRmsResidual / (circleTolerance * 1.3),
          1 - circle.p90Residual / (circleTolerance * 2.2),
          (circle.signCoherence - .76) / .24,
          // Sweep is already checked above. Scaling confidence toward pi
          // rejected even a perfect short arc solely for being short.
        ]);
        if (confidence >=
            configuration.minimumAcceptanceConfidenceFor(
              PawStrokeAssistKind.arc,
            )) {
          candidates.add(PawStrokeAssistClassification(
            kind: PawStrokeAssistKind.arc,
            confidence: confidence,
            circleFit: circle,
          ));
        }
      }
    }

    final turnVariation = _turnVariation(points);
    final fitTolerance = configuration.beautificationPolicy.fitToleranceFor(
      scale,
      sampleCount: samples.length,
      pathLength: pathLength,
      turnVariation: turnVariation,
    );
    final fairing = const PawHeldCurveFairer().fair(
      samples,
      maximumDisplacement: configuration.fidelityCorridorFor(scale),
    );
    final curveFit = PawHeldCurveFitter(
      maximumSegments: configuration.beautificationPolicy.maximumCurveSegments,
    ).fit(fairing.samples, tolerance: fitTolerance);
    if (curveFit.segments.isNotEmpty &&
        curveFit.maximumResidual <= configuration.fidelityCorridorFor(scale)) {
      var signChanges = 0;
      var previousSign = 0;
      for (var index = 1; index < points.length - 1; index++) {
        final turn =
            _turnAngle(points[index - 1], points[index], points[index + 1]);
        if (turn.abs() < .04) continue;
        final sign = turn < 0 ? -1 : 1;
        if (previousSign != 0 && sign != previousSign) signChanges++;
        previousSign = sign;
      }
      final kind = signChanges > 0 || curveFit.segments.length > 2
          ? PawStrokeAssistKind.continuousCurve
          : PawStrokeAssistKind.curve;
      candidates.add(PawStrokeAssistClassification(
        kind: kind,
        confidence:
            (1 - curveFit.rmsResidual / math.max(.001, fitTolerance * 2))
                .clamp(0.0, 1.0),
        curveFit: curveFit,
        curveFairing: fairing,
        closureTopology: ellipseClosure,
      ));
    }

    final hasCanonicalCandidate = candidates.any(
      (candidate) => switch (candidate.kind) {
        PawStrokeAssistKind.line ||
        PawStrokeAssistKind.polyline ||
        PawStrokeAssistKind.arc ||
        PawStrokeAssistKind.ellipse ||
        PawStrokeAssistKind.circle ||
        PawStrokeAssistKind.triangle ||
        PawStrokeAssistKind.quadrilateral =>
          true,
        _ => false,
      },
    );
    final scored = <PawStrokeAssistClassification>[
      for (final candidate in candidates)
        candidate.withScore(_scoreCandidate(
          candidate,
          fitTolerance: fitTolerance,
          closed: closed,
          hasCanonicalCandidate: hasCanonicalCandidate,
        )),
    ]..sort((left, right) {
        final cost = left.score.totalCost.compareTo(right.score.totalCost);
        if (cost != 0) return cost;
        return right.confidence.compareTo(left.confidence);
      });
    return List<PawStrokeAssistClassification>.unmodifiable(scored);
  }
}

Map<String, Object> _canonicalClosureTopology(
  List<Offset> points, {
  required double pathLength,
  required double scale,
  required double signedSweep,
  required double perimeter,
}) {
  final gap = (points.last - points.first).distance;
  final gapToPath = gap / math.max(1, pathLength);
  final gapToBounds = gap / math.max(1, scale);
  final missingArcFraction = gap / math.max(1, perimeter);
  final startTangent =
      _normalized(points[math.min(2, points.length - 1)] - points.first);
  final endTangent =
      _normalized(points.last - points[math.max(0, points.length - 3)]);
  final tangentCompatibility =
      startTangent.dx * endTangent.dx + startTangent.dy * endTangent.dy;
  final previousEndGap =
      (points[math.max(0, points.length - 3)] - points.first).distance;
  final previousStartGap =
      (points.last - points[math.min(2, points.length - 1)]).distance;
  final endpointConvergence = math.min(
    previousEndGap <= .001 ? 0 : 1 - gap / previousEndGap,
    previousStartGap <= .001 ? 0 : 1 - gap / previousStartGap,
  );
  final tangentCompatible = tangentCompatibility >= .35 ||
      (signedSweep.abs() >= math.pi * 1.9 && gapToPath <= .08);
  final passed = gapToPath <= .12 &&
      gapToBounds <= .24 &&
      missingArcFraction <= .18 &&
      signedSweep.abs() >= math.pi * 1.8 &&
      tangentCompatible;
  return <String, Object>{
    'passed': passed,
    'endpoint_gap': gap,
    'gap_to_path': gapToPath,
    'gap_to_bounds': gapToBounds,
    'missing_closing_arc_fraction': missingArcFraction,
    'signed_sweep': signedSweep,
    'endpoint_tangent_compatibility': tangentCompatibility,
    'endpoint_convergence': endpointConvergence,
  };
}

PawStrokeCandidateScore _scoreCandidate(
  PawStrokeAssistClassification candidate, {
  required double fitTolerance,
  required bool closed,
  required bool hasCanonicalCandidate,
}) {
  final fit = candidate.curveFit;
  if (fit != null) {
    final passedClosedTopology =
        closed && candidate.closureTopology['passed'] == true;
    return PawStrokeCandidateScore(
      geometryResidual:
          (fit.rmsResidual / math.max(.001, fitTolerance)).clamp(0.0, 1.0),
      maximumResidual: (fit.maximumResidual / math.max(.001, fitTolerance * 2))
          .clamp(0.0, 1.0),
      complexityPenalty: .035 +
          .12 * fit.segments.length / math.max(1, fit.sourcePointCount - 1) +
          (fit.segments.length == 1 &&
                  fit.sourcePointCount >= 8 &&
                  fit.maximumResidual > fitTolerance * .55
              ? .28
              : 0),
      // A fitted free curve is allowed to close, but it must not outrank an
      // accepted canonical closed shape merely because it uses many cubics.
      // If no canonical candidate survived, a topology-valid closed curve is
      // still preferable to falling back to FREEFORM_SMOOTH.
      closurePenalty: closed
          ? hasCanonicalCandidate
              ? .55
              : passedClosedTopology
                  ? 0
                  : .55
          : 0,
      sweepPenalty: hasCanonicalCandidate ? .18 : 0,
      turnCoherence: .82,
      topologyPenalty: candidate.kind == PawStrokeAssistKind.curve &&
              fit.salientCuspIndices.isNotEmpty
          ? .14
          : 0,
    );
  }
  if (candidate.kind == PawStrokeAssistKind.freeformSmooth) {
    return const PawStrokeCandidateScore(
      geometryResidual: 1,
      maximumResidual: 1,
      complexityPenalty: .3,
      turnCoherence: .5,
    );
  }
  final residual = (1 - candidate.confidence).clamp(0.0, 1.0);
  final complexity = switch (candidate.kind) {
    PawStrokeAssistKind.line => .01,
    PawStrokeAssistKind.arc => .025,
    PawStrokeAssistKind.circle || PawStrokeAssistKind.ellipse => .035,
    PawStrokeAssistKind.triangle || PawStrokeAssistKind.quadrilateral => .05,
    PawStrokeAssistKind.polyline => .065,
    _ => .1,
  };
  final coherence = candidate.circleFit?.signCoherence ??
      candidate.ellipseFit?.signCoherence ??
      1.0;
  return PawStrokeCandidateScore(
    geometryResidual: residual,
    maximumResidual: residual,
    complexityPenalty: complexity,
    turnCoherence: coherence,
  );
}
