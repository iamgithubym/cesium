attribute vec3 position3DHigh;
attribute vec3 position3DLow;

#ifndef COLUMBUS_VIEW_2D
attribute vec4 startHiAndForwardOffsetX;
attribute vec4 startLoAndForwardOffsetY;
attribute vec4 startNormalAndForwardOffsetZ;
attribute vec4 endNormalAndTextureCoordinateNormalizationX;
attribute vec4 rightNormalAndTextureCoordinateNormalizationY;
#else
attribute vec4 startHiLo2D;
attribute vec4 offsetAndRight2D;
attribute vec4 startEndNormals2D;
attribute vec2 texcoordNormalization2D;
#endif

attribute float batchId;

varying vec4 v_startPlaneNormalEcAndHalfWidth;
varying vec4 v_endPlaneNormalEcAndBatchId;
varying vec4 v_rightPlaneEC;
varying vec4 v_endEcAndStartEcX;
varying vec4 v_texcoordNormalizationAndStartEcYZ;

// For materials
#ifdef WIDTH_VARYING
varying float v_width;
#endif
#ifdef ANGLE_VARYING
varying float v_polylineAngle;
#endif

#ifdef PER_INSTANCE_COLOR
varying vec4 v_color;
#endif

void main()
{
#ifdef COLUMBUS_VIEW_2D
    vec3 ecStart = (czm_modelViewRelativeToEye * czm_translateRelativeToEye(vec3(0.0, startHiLo2D.xy), vec3(0.0, startHiLo2D.zw))).xyz;

    vec3 forwardDirectionEC = czm_normal * vec3(0.0, offsetAndRight2D.xy);
    vec3 ecEnd = forwardDirectionEC + ecStart;
    forwardDirectionEC = normalize(forwardDirectionEC);

    // Right plane
    v_rightPlaneEC.xyz = czm_normal * vec3(0.0, offsetAndRight2D.zw);
    v_rightPlaneEC.w = -dot(v_rightPlaneEC.xyz, ecStart);

    // start plane
    vec4 startPlaneEC;
    startPlaneEC.xyz =  czm_normal * vec3(0.0, startEndNormals2D.xy);
    startPlaneEC.w = -dot(startPlaneEC.xyz, ecStart);

    // end plane
    vec4 endPlaneEC;
    endPlaneEC.xyz =  czm_normal * vec3(0.0, startEndNormals2D.zw);
    endPlaneEC.w = -dot(endPlaneEC.xyz, ecEnd);

    v_texcoordNormalizationAndStartEcYZ.xy = vec2(abs(texcoordNormalization2D.x), texcoordNormalization2D.y);

#else // COLUMBUS_VIEW_2D
    vec3 ecStart = (czm_modelViewRelativeToEye * czm_translateRelativeToEye(startHiAndForwardOffsetX.xyz, startLoAndForwardOffsetY.xyz)).xyz;
    vec3 offset = czm_normal * vec3(startHiAndForwardOffsetX.w, startLoAndForwardOffsetY.w, startNormalAndForwardOffsetZ.w);
    vec3 ecEnd = ecStart + offset;

    vec3 forwardDirectionEC = normalize(offset);

    // start plane
    vec4 startPlaneEC;
    startPlaneEC.xyz = czm_normal * startNormalAndForwardOffsetZ.xyz;
    startPlaneEC.w = -dot(startPlaneEC.xyz, ecStart);

    // end plane
    vec4 endPlaneEC;
    endPlaneEC.xyz = czm_normal * endNormalAndTextureCoordinateNormalizationX.xyz;
    endPlaneEC.w = -dot(endPlaneEC.xyz, ecEnd);

    // Right plane
    v_rightPlaneEC.xyz = czm_normal * rightNormalAndTextureCoordinateNormalizationY.xyz;
    v_rightPlaneEC.w = -dot(v_rightPlaneEC.xyz, ecStart);

    v_texcoordNormalizationAndStartEcYZ.xy = vec2(abs(endNormalAndTextureCoordinateNormalizationX.w), rightNormalAndTextureCoordinateNormalizationY.w);

#endif // COLUMBUS_VIEW_2D

    v_endEcAndStartEcX.xyz = ecEnd;
    v_endEcAndStartEcX.w = ecStart.x;
    v_texcoordNormalizationAndStartEcYZ.zw = ecStart.yz;

#ifdef PER_INSTANCE_COLOR
    v_color = czm_batchTable_color(batchId);
#endif // PER_INSTANCE_COLOR

    // Compute a normal along which to "push" the position out, extending the miter depending on view distance.
    // Position has already been "pushed" by unit length along miter normal, and miter normals are encoded in the planes.
    // Decode the normal to use at this specific vertex, push the position back, and then push to where it needs to be.
    vec4 positionRelativeToEye = czm_computePosition();

    // Check distance to the end plane and start plane, pick the plane that is closer
    vec4 positionEC = czm_modelViewRelativeToEye * positionRelativeToEye; // w = 1.0, see czm_computePosition
    float absStartPlaneDistance = abs(czm_planeDistance(startPlaneEC, positionEC.xyz));
    float absEndPlaneDistance = abs(czm_planeDistance(endPlaneEC, positionEC.xyz));
    vec3 planeDirection = czm_branchFreeTernary(absStartPlaneDistance < absEndPlaneDistance, startPlaneEC.xyz, endPlaneEC.xyz);
    vec3 upOrDown = normalize(cross(v_rightPlaneEC.xyz, planeDirection)); // Points "up" for start plane, "down" at end plane.
    vec3 normalEC = normalize(cross(planeDirection, upOrDown));           // In practice, the opposite seems to work too.

    // Determine distance along normalEC to push for a volume of appropriate width.
    // Make volumes about double pixel width for a conservative fit - in practice the
    // extra cost here is minimal compared to the loose volume heights.
    //
    // N = normalEC (guaranteed "right-facing")
    // R = rightEC
    // p = angle between N and R
    // w = distance to push along R if R == N
    // d = distance to push along N
    //
    //   N   R
    //  { \ p| }      * cos(p) = dot(N, R) = w / d
    //  d\ \ |  |w    * d = w / dot(N, R)
    //    { \| }
    //       o---------- polyline segment ---->
    //
    float width = czm_batchTable_width(batchId);
#ifdef WIDTH_VARYING
    v_width = width;
#endif

    v_startPlaneNormalEcAndHalfWidth.xyz = startPlaneEC.xyz;
    v_startPlaneNormalEcAndHalfWidth.w = width * 0.5;

    v_endPlaneNormalEcAndBatchId.xyz = endPlaneEC.xyz;
    v_endPlaneNormalEcAndBatchId.w = batchId;

    width = width * max(0.0, czm_metersPerPixel(positionEC)); // width = distance to push along R
    width = width / dot(normalEC, v_rightPlaneEC.xyz); // width = distance to push along N

    // Determine if this vertex is on the "left" or "right"
#ifdef COLUMBUS_VIEW_2D
        normalEC *= sign(texcoordNormalization2D.x);
#else
        normalEC *= sign(endNormalAndTextureCoordinateNormalizationX.w);
#endif

    positionEC.xyz += width * normalEC;
    gl_Position = czm_projection * positionEC;

#ifdef ANGLE_VARYING
    // Approximate relative screen space direction of the line.
    vec2 approxLineDirection = normalize(vec2(forwardDirectionEC.x, -forwardDirectionEC.y));
    approxLineDirection.y = czm_branchFreeTernary(approxLineDirection.x == 0.0 && approxLineDirection.y == 0.0, -1.0, approxLineDirection.y);
    v_polylineAngle = czm_fastApproximateAtan(approxLineDirection.x, approxLineDirection.y);
#endif
}
