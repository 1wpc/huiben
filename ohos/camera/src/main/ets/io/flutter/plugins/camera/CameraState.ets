// Copyright (c) 2024 Huawei Device Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_HW file.
// Based on CameraState.java originally written by
// Copyright 2013 The Flutter Authors.

export enum CameraState {
  // Avoid repetition
  /** Idle, showing preview and not capturing anything. */
  STATE_PREVIEW,

  // Avoid repetition
  /** Starting and waiting for autofocus to complete. */
  STATE_WAITING_FOCUS,

  // Avoid repetition
  /** Start performing autoexposure. */
  STATE_WAITING_PRECAPTURE_START,

  // Avoid repetition
  /** waiting for autoexposure to complete. */
  STATE_WAITING_PRECAPTURE_DONE,

  // Avoid repetition
  /** Capturing an image. */
  STATE_CAPTURING,
}