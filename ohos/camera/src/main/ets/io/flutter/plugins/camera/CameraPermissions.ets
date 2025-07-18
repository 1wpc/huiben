// Copyright (c) 2024 Huawei Device Co., Ltd.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE_HW file.
// Based on CameraPermissions.java originally written by
// Copyright 2013 The Flutter Authors.

import bundleManager from '@ohos.bundle.bundleManager';
import abilityAccessCtrl, { PermissionRequestResult, Permissions } from '@ohos.abilityAccessCtrl';
import { BusinessError } from '@ohos.base';

type ResultCallback = (errCode: string | null, errDesc: string | null) => void;

const photoPermission: Array<Permissions> =
  ['ohos.permission.CAMERA'];

const videoPermission: Array<Permissions> =
  ['ohos.permission.CAMERA',
    'ohos.permission.MICROPHONE'];

async function checkAccessToken(permission: Permissions): Promise<abilityAccessCtrl.GrantStatus> {
  let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
  let grantStatus: abilityAccessCtrl.GrantStatus = abilityAccessCtrl.GrantStatus.PERMISSION_DENIED;

  // 获取应用程序的accessTokenID
  let tokenId: number = 0;
  try {
    let bundleInfo: bundleManager.BundleInfo = await bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION);
    let appInfo: bundleManager.ApplicationInfo = bundleInfo.appInfo;
    tokenId = appInfo.accessTokenId;
  } catch (error) {
    let err: BusinessError = error as BusinessError;
    console.error(`Failed to get bundle info for self. Code is ${err.code}, message is ${err.message}`);
  }

  // 校验应用是否被授予权限
  try {
    grantStatus = await atManager.checkAccessToken(tokenId, permission);
  } catch (error) {
    let err: BusinessError = error as BusinessError;
    console.error(`Failed to check access token. Code is ${err.code}, message is ${err.message}`);
  }

  return grantStatus;
}

async function checkPermissions(permissions: Array<Permissions>): Promise<boolean> {
  let grantStatus: abilityAccessCtrl.GrantStatus = await checkAccessToken(permissions[0]);
  return grantStatus === abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED;
}

export class CameraPermissions {
  async requestPermissions(
    context: Context,
    enableAudio: boolean,
    callback: ResultCallback
  ) {
    const hasCameraPermission: boolean = await checkPermissions(photoPermission);
    const hasAudioPermission: boolean = enableAudio && await checkPermissions(videoPermission);

    if (!hasCameraPermission || !hasAudioPermission) {
      let atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();

      // requestPermissionsFromUser会判断权限的授权状态来决定是否唤起弹窗
      atManager.requestPermissionsFromUser(context, enableAudio ? videoPermission : photoPermission)
        .then((data: PermissionRequestResult) => {
          let grantStatus: Array<number> = data.authResults;
          let length: number = grantStatus.length;
          for (let i = 0; i < length; i++) {
            if (grantStatus[i] !== 0) {
              // 用户拒绝授权，提示用户必须授权才能访问当前页面的功能，并引导用户到系统设置中打开相应的权限
              callback('errCode', '未授权相机权限');
              return;
            }
          }
          // 用户授权，可以继续访问目标操作
          callback(null, null);
        }).catch((err: BusinessError) => {
        console.error(`Failed to request permissions from user. Code is ${err.code}, message is ${err.message}`);
        callback(String(err.code), err.message);
      })
    } else {
      // Permissions already exist. Call the callback with success.
      callback(null, null);
    }
  }
}



