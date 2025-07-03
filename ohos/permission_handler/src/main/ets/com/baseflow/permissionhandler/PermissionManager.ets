/*
* Copyright (c) 2023 Hunan OpenValley Digital Industry Development Co., Ltd.
* Licensed under the Apache License, Version 2.0 (the "License");
* you may not use this file except in compliance with the License.
* You may obtain a copy of the License at
*
*     http://www.apache.org/licenses/LICENSE-2.0
*
* Unless required by applicable law or agreed to in writing, software
* distributed under the License is distributed on an "AS IS" BASIS,
* WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
* See the License for the specific language governing permissions and
* limitations under the License.
*/

import common from '@ohos.app.ability.common';
import PermissionConstants from './PermissionConstants';
import abilityAccessCtrl, { Permissions } from '@ohos.abilityAccessCtrl';
import bundleManager from '@ohos.bundle.bundleManager';
import PermissionUtils from './PermissionUtils';
import Log from '@ohos/flutter_ohos/src/main/ets/util/Log';
import UIAbility from '@ohos.app.ability.UIAbility';
import ArrayList from '@ohos.util.ArrayList';
import { ErrorCallback } from './ErrorCallback';
import { BusinessError, Callback } from '@ohos.base';
import { notificationManager } from '@kit.NotificationKit';

export class PermissionManager {
  private tokenId: number | null = null;

  private atManager: abilityAccessCtrl.AtManager;

  private ongoing: boolean = false;

  private ability: UIAbility | null = null;

  private successCallback: RequestPermissionsSuccessCallback | null = null;

  private requestResults:Map<number, number> | null = null;

  constructor() {
    this.atManager = abilityAccessCtrl.createAtManager();
  }

  /**
   * 检测权限状态
   *
   * @param permission 权限
   * @param context 上下文
   * @param successCallback 回调结果
   */
  public checkPermissionStatus(permission: number, context: common.Context,
    successCallback: CheckPermissionSuccessCallback): void {
      this.determinePermissionStatus(permission, successCallback);
   }

  private determinePermissionStatus(permission: number, successCallback: CheckPermissionSuccessCallback): void {
    if (permission == PermissionConstants.PERMISSION_GROUP_NOTIFICATION) {
      let enabled = notificationManager.isNotificationEnabledSync();
      if (enabled) {
        successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
      } else {
        successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_DENIED);
      }
      return;
    }
    if (permission == PermissionConstants.PERMISSION_GROUP_BLUETOOTH) {
      this.checkBluetoothPermissionStatus(successCallback);
      return;
    }
    PermissionUtils.getManifestNames(permission, (names: ArrayList<string>) => {
      if (names == null || names == undefined) {
        Log.d(PermissionConstants.LOG_TAG, "No android specific permissions needed for: " + permission);
        successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
        return;
      }
      if (names.length == 0) {
        Log.d(PermissionConstants.LOG_TAG, "No permissions found in manifest for: " + names + permission);
        if (permission == PermissionConstants.PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS) {
          successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_DENIED);
          return;
        }
        if (permission == PermissionConstants.PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE) {
          successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
          return;
        }
        successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_DENIED);
        return;
      }
      for (let name of names) {
        if (permission == PermissionConstants.PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS) {
          successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_DENIED);
          return;
        }
        if (permission == PermissionConstants.PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE) {
          successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
          return;
        }
        if (permission == PermissionConstants.PERMISSION_GROUP_SYSTEM_ALERT_WINDOW) {
          successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
          return;
        }
        if (permission == PermissionConstants.PERMISSION_GROUP_REQUEST_INSTALL_PACKAGES) {
          successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
          return;
        }
        if (this.tokenId == null || this.tokenId == undefined) {
          let bundleInfo = bundleManager.getBundleInfoForSelfSync(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
          this.tokenId = bundleInfo.appInfo.accessTokenId;
        }
        let status: abilityAccessCtrl.GrantStatus  = this.atManager.verifyAccessTokenSync(this.tokenId, name as Permissions);
        if (status != abilityAccessCtrl.GrantStatus.PERMISSION_GRANTED) {
          successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_DENIED);
          return;
        }
      }
      successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
    });
  }

  requestPermissions(permissions: ArrayList<number>, ability: UIAbility,
    successCallback: RequestPermissionsSuccessCallback, errorCallback: ErrorCallback ): void {
    if (this.ongoing) {
      errorCallback.onError( "PermissionHandler.PermissionManager",
        "A request for permissions is already running, please wait for it to finish before doing another request (note that you can request multiple permissions at the same time).");
      return;
    }
    if (ability == null) {
      Log.d(PermissionConstants.LOG_TAG, "Unable to detect current Activity.");
      errorCallback.onError(
        "PermissionHandler.PermissionManager",
        "Unable to detect current Android Activity.");
      return;
    }
    this.successCallback = successCallback;
    this.ability = ability;
    this.requestResults = new Map();
    this.getPermissionToRequest(permissions, (permissionsToRequest: ESObject) => {
      if (permissionsToRequest?.length > 0) {
        try {
          this.atManager.requestPermissionsFromUser(ability.context, permissionsToRequest.convertToArray(), (error, result) => {
            this.ongoing = false;
            let grant: Array<number> = result.authResults;
            let permissionNames: Array<string> = result.permissions;
            for (let i = 0; i < permissionNames.length; i++) {
              let permissionName: string = permissionNames[i];
              let authResult: number = grant[i];
              let permission: number = PermissionUtils.parseOhosName(permissionName);
              if (permission == PermissionConstants.PERMISSION_GROUP_UNKNOWN)
                continue;
              if (permission == PermissionConstants.PERMISSION_GROUP_NOTIFICATION) {
                notificationManager.requestEnableNotification(this.ability?.context).then(() => {
                  let enabled = notificationManager.isNotificationEnabledSync();
                  if (enabled) {
                    this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_NOTIFICATION, PermissionConstants.PERMISSION_STATUS_GRANTED);
                  } else {
                    this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_NOTIFICATION, PermissionConstants.PERMISSION_STATUS_DENIED);
                  }
                  this.successCallback?.onSuccess(this.requestResults as Map<number,number>);
                }).catch((err: BusinessError) => {
                  this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_NOTIFICATION, PermissionConstants.PERMISSION_STATUS_DENIED);
                  this.successCallback?.onSuccess(this.requestResults as Map<number,number>);
                });
                return;
              } else if (permission == PermissionConstants.PERMISSION_GROUP_MICROPHONE) {
                this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_MICROPHONE, PermissionUtils.toPermissionStatus(authResult));
                this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_SPEECH, PermissionUtils.toPermissionStatus(authResult));
              } else if (permission == PermissionConstants.PERMISSION_GROUP_LOCATION_ALWAYS) {
                this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_LOCATION_ALWAYS, PermissionUtils.toPermissionStatus(authResult));
              } else if (permission == PermissionConstants.PERMISSION_GROUP_LOCATION) {

                if (permissionName == 'ohos.permission.APPROXIMATELY_LOCATION') {
                  this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_LOCATION_WHEN_IN_USE, PermissionUtils.toPermissionStatus(authResult));
                }
                if (permissionName == 'ohos.permission.LOCATION') {
                  this.requestResults?.set(PermissionConstants.PERMISSION_GROUP_LOCATION, PermissionUtils.toPermissionStatus(authResult));
                }
                
              } else {
                // this.requestResults?.set(permission, PermissionUtils.toPermissionStatus(authResult));
                let hasDialog: boolean | null = null;
                if (result.dialogShownResults != undefined) {
                  hasDialog = result.dialogShownResults[i];
                }
                if (authResult == -1 && hasDialog == false) {
                  //用户已经拒绝，需要打开设置页面进行授权
                  this.requestResults?.set(permission, PermissionConstants.PERMISSION_STATUS_NEVER_ASK_AGAIN);
                } else {
                  this.requestResults?.set(permission, PermissionUtils.toPermissionStatus(authResult));
                }
              }
              PermissionUtils.updatePermissionShouldShowStatus(permission);
            }
            this.successCallback?.onSuccess(this.requestResults as Map<number,number>);
          });
        } catch (error) {
          this.ongoing = false;
          this.successCallback?.onSuccess(this.requestResults as Map<number,number>);
        }
      } else {
        this.ongoing = false;
        this.successCallback?.onSuccess(this.requestResults as Map<number,number>);
      }
    });
  }

  private getPermissionToRequest(permissions: ArrayList<number>, callback: Callback<ArrayList<ESObject>>): void {
    let permissionsToRequest: ArrayList<ESObject>  = new ArrayList();
    let size: number = permissions.length;
    for (let permission of permissions) {
      this.determinePermissionStatus(permission, {
        onSuccess : (permissionStatus:ESObject) => {
          if (permissionStatus == PermissionConstants.PERMISSION_STATUS_GRANTED) {
            if (!this.requestResults?.has(permission)) {
              this.requestResults?.set(permission, PermissionConstants.PERMISSION_STATUS_GRANTED);
            }
            size -= 1;
            if (size == 0) {
              callback(permissionsToRequest);
            }
            return;
          }
          PermissionUtils.getManifestNames(permission, (names:ArrayList<string>) => {
            if (names == null || names.length == 0) {
              if (this.requestResults && !this.requestResults.has(permission)) {
                if (permission == PermissionConstants.PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS) {
                  this.requestResults.set(permission, PermissionConstants.PERMISSION_STATUS_DENIED);
                }
                if (permission == PermissionConstants.PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE) {
                  this.requestResults.set(permission, PermissionConstants.PERMISSION_STATUS_GRANTED);
                }
                if (permission == PermissionConstants.PERMISSION_GROUP_SYSTEM_ALERT_WINDOW) {
                  this.requestResults.set(permission, PermissionConstants.PERMISSION_STATUS_GRANTED);
                }
              }
              size -= 1;
              if (size == 0) {
                callback(permissionsToRequest);
              }
              return;
            }
            if (permission == PermissionConstants.PERMISSION_GROUP_IGNORE_BATTERY_OPTIMIZATIONS) {
              // don't support
            } else if (permission == PermissionConstants.PERMISSION_GROUP_MANAGE_EXTERNAL_STORAGE) {
              // don't support
            } else if (permission == PermissionConstants.PERMISSION_GROUP_SYSTEM_ALERT_WINDOW) {
              // don't support
            } else {
              for (let name of names) {
                permissionsToRequest.add(name);
              }
            }
            size -= 1;
            if (size == 0) {
              callback(permissionsToRequest);
            }
          });
        }
      } as ESObject);
    }
  }

  private checkBluetoothPermissionStatus(successCallback: CheckPermissionSuccessCallback): void {
    PermissionUtils.getManifestNames(PermissionConstants.PERMISSION_GROUP_BLUETOOTH, (permissions: ESObject) => {
      let missingInManifest: boolean = permissions == null || permissions.isEmpty();
      if (missingInManifest) {
        Log.d(PermissionConstants.LOG_TAG, "Bluetooth permission missing in manifest");
        successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_DENIED);
      } else {
        // successCallback.onSuccess(PermissionConstants.PERMISSION_STATUS_GRANTED);
        this.checkPermission( {
          onSuccess: (permissionStatus: number) => {
            successCallback.onSuccess(permissionStatus == -1 ? 0 : 1);
          }
        } as ESObject ,'ohos.permission.ACCESS_BLUETOOTH');
      }
    });
  }

  private checkPermission(successCallback: CheckPermissionSuccessCallback, permissionName: Permissions): void {
    if (this.tokenId == null || this.tokenId == undefined) {
      bundleManager.getBundleInfoForSelf(bundleManager.BundleFlag.GET_BUNDLE_INFO_WITH_APPLICATION)
        .then((bundleInfo)=> {
        this.tokenId = bundleInfo.appInfo.accessTokenId;
          successCallback.onSuccess(this.atManager.verifyAccessTokenSync(this.tokenId, permissionName));
      });
    } else {
      successCallback.onSuccess(this.atManager.verifyAccessTokenSync(this.tokenId, permissionName));
    }
  }

  shouldShowRequestPermissionRationale(permission: number,
    callback: ShouldShowRequestPermissionRationaleSuccessCallback, errorCallback: ErrorCallback): void {
    callback?.onSuccess(false);
  }
}

export interface CheckPermissionSuccessCallback {
  onSuccess(permissionStatus: number): void;
}

export interface RequestPermissionsSuccessCallback {
  onSuccess(results: Map<number, number> ) : void;
}

export interface ShouldShowRequestPermissionRationaleSuccessCallback {
  onSuccess(shouldShowRequestPermissionRationale: boolean): void;
}

